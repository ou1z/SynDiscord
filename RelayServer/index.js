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
    client.on('message', async message => {
        let parsed;
        try {
            parsed = JSON.parse(message);
        } catch { return }

        if (!parsed.Action || !parsed.Token) return;
        const { Action, Token } = parsed;

        if (Action == "START_RELAY" && authorizedTokens[Token]) {
            const myClient = new WebSocket("wss://gateway.discord.gg/?v=6&encoding=json")
            myWebsocketClients[Token] = myClient;
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
                return setInterval(() => {
                    myClient.send(JSON.stringify({op: 2, d: null}));
                }, ms)
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
})

app.listen(PORT, () => console.info(`Server running on (Port => ${PORT})`))