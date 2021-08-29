
const fetch = require('node-fetch')
const express = require('express')
const WebSocket = require('ws')
const app = express()
require('express-ws')(app)

const PORT = process.env.PORT || 3000;

async function FetchInformation(token) {
    const info = await fetch('https://www.discord.com/api/v9/users/@me', {
        headers: {
            Authorization: token
        }
    });
    return await info.text();
}

const myWebsocketClients = {};
const authorizedTokens = {};
const clientRelayConnections = {};
const clientIntervals = {};

express.getUniqueID = function () {
    function s4() {
        return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1);
    }
    return s4() + s4() + '-' + s4();
};

app.use(express.json())

app.use((req, res, next) => {

    if (req.headers['syn-fingerprint']) {
        delete req.headers['syn-fingerprint']
        delete req.headers['syn-user-identifier']
        delete req.headers['user-agent']
    }
    req.headers.host = 'canary.discord.com'
    
    next()
})

app.use('/proxy', async (req, res) => {
    const url = 'https://www.discord.com' + req.path
    const headers = req.headers
    let r = null

    headers['content-type'] = 'application/json'

    if (req.method != 'GET' && req.method != 'HEAD') {
        r = await fetch(url, {
            method: req.method,
            headers,
            body: JSON.stringify(req.body)
        })
    } else {
        r = await fetch(url, {
            method: req.method,
            headers
        })
    }

    for (let h of Object.keys(r.headers)) {
        res.setHeader(h, r.headers[h])
    }

    res.send(await r.text())
})


app.get('/login', async (req,res) => {
    const token = req.headers.authorization
    if (!token) {
        return res.send('{}');
    }
    const info = await FetchInformation(token)
    if (JSON.parse(info).username) {
        authorizedTokens[token] = info;
    }
    res.send(info);
})

app.ws('/ws', async (client, req) => {
    client.id = express.getUniqueID()
    

    client.on('message', async message => {
        let parsed;
        try {
            parsed = JSON.parse(message);
        } catch { return }

        if (!parsed.Action || !parsed.Token) return;
        const { Action, Token } = parsed;

        if (Action == "START_RELAY" && authorizedTokens[Token]) {
            const myClient = new WebSocket("wss://gateway.discord.gg/?v=6&encoding=json")
            if (!myWebsocketClients[Token]) {
                myWebsocketClients[Token] = [];
            }
            myWebsocketClients[Token].push(myClient);
            clientRelayConnections[client.id] = myClient;
            clientIntervals[client.id] = [];
            let interval = 0;

            let payload = {
                op: 2,
                d: {
                    token: Token,
                    properties: {
                        $os: "linux",
                        $browser: "chrome",
                        $device: "chrome"
                    }
                }
            }

            const heartbeat = ms => {
                let newInterval = setInterval(() => {
                    myClient.send(JSON.stringify({op: 2, d: null}));
                }, ms)
                if (clientIntervals[client.id]) {
                    clientIntervals[client.id].push(newInterval);
                }
                return newInterval 
            }

            myClient.onopen = () => {
                myClient.send(JSON.stringify(payload));
            }

            myClient.onmessage = message => {
                const {t,event,op,d} = JSON.parse(message.data);

                if (op === 10) {
                    interval = heartbeat(d.heartbeat_interval)
                }

                client.send(JSON.stringify({
                    Event: t,
                    Data: d
                }));
            }

            myClient.onerror = err => {
                console.error(err);
            }
        }
    })

    client.on('close', () => {
        if (myWebsocketClients[client.id]) {
            for (let c of myWebsocketClients[client.id]) {
                c.close();
            }
            delete myWebsocketClients[client.id];
        }
        if (clientIntervals[client.id]) {
            for (let interval of clientIntervals[client.id]) {
                clearInterval(interval);
            }
            delete clientIntervals[client.id];
        }
    })
})

app.listen(PORT, () => console.info(`Server running on (Port => ${PORT})`))
