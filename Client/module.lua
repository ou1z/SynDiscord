if not syn or not syn.websocket then
    return game.Players.LocalPlayer:Kick('Your exploit does not support websockets.')
end
local RELAY_ROOT = 'syn-discord-wrapper.herokuapp.com' -- needed, since synapse doesnt support wss

local SynDiscord = {
    Client = {},
    Utils = {},
    Embeds = {},
    WEBSOCKET_RELAY_SERVER = string.format('ws://%s/ws', RELAY_ROOT),
    API_ROOT = string.format('http://%s/', RELAY_ROOT)
}
SynDiscord.API_PROXY = SynDiscord.API_ROOT .. 'proxy/api/v9/'

do -- Client Functions
    SynDiscord.Client.__index = SynDiscord.Client

    function SynDiscord.Client.new()
        local Client = setmetatable({}, SynDiscord.Client)
        Client.__meta__ = {
            EventListeners = {};
            WebsocketClient = syn.websocket.connect(SynDiscord.WEBSOCKET_RELAY_SERVER);
        }
        Client:StartEventLoop()
        return Client
    end

    function SynDiscord.Client:on(EventName, Callback)
        local Listeners = self.__meta__.EventListeners

        if Listeners[EventName] == nil then
            Listeners[EventName] = { Callback }
        else
            table.insert(Listeners[EventName], Callback)
        end

        return true
    end

    function SynDiscord.Client:login(token)
        self.User = { Token = token }
        local res = self:Request({
            Url = SynDiscord.API_ROOT.."login"
        }).Body
        local Information = SynDiscord.Utils:JSONDecode(res)
        SynDiscord.Utils:ConcatTables(self.User, Information)
        self.__meta__.WebsocketClient:Send(SynDiscord.Utils:JSONEncode({
            Action = "START_RELAY",
            Token = self.User.Token
        }))
        return self.User
    end

    function SynDiscord.Client:Request(Tbl)
        if Tbl == nil or typeof(Tbl) ~= 'table' or Tbl.Url == nil then
            return
        end
        if Tbl.Headers == nil then
            Tbl.Headers = {}
        end
        Tbl.Headers['Authorization'] = self.User.Token
        return syn.request(Tbl)
    end

    function SynDiscord.Client:StartEventLoop()
        local client = self.__meta__.WebsocketClient

        client.OnMessage:Connect(function(data)
            local parsed = SynDiscord.Utils:JSONDecode(data)
           

            if parsed.Event then
                local Event = SynDiscord.Utils:SnakeToCamelCase(parsed.Event:lower())

                if Event == 'messageCreate' then
                    local message = parsed.Data

                    message.channel = {
                        id = message.channel_id
                    }
                    function message.channel.send(content, tbl)
                        local t = {
                            content = content
                        }
                        if tbl then
                            for i,v in pairs(tbl) do
                                t[i] = v
                            end
                        end
                        local res = self:Request({
                            Url = SynDiscord.API_PROXY .. string.format('channels/%s/messages', message.channel_id),
                            Method = 'POST',
                            Headers = {
                                ['Content-Type'] = 'application/json'  
                            },
                            Body = SynDiscord.Utils:JSONEncode(t)
                        })
                        return res.Body
                    end

                    function message.react(emoji)
                        local emoji_urlencoded = game:GetService("HttpService"):UrlEncode(emoji)
                        local res = self:Request({
                            Url = SynDiscord.API_PROXY .. string.format('channels/%s/messages/%s/reactions/%s/%%40me', message.channel_id, message.id, emoji_urlencoded),
                            Method = 'PUT',
                            Headers = {
                                ['Content-Type'] = 'application/json'  
                            }
                        })
                        return res.Body
                    end

                    function message.delete()
                        local res = self:Request({
                            Url = SynDiscord.API_PROXY .. string.format('channels/%s/messages/%s', message.channel_id, message.id),
                            Method = 'DELETE'
                        })
                        return res.Body
                    end

                    function message.reply(content, tbl)
                        local t = {
                            content = content,
                            message_reference = {
                                channel_id = message.channel.id,
                                guild_id = message.guild_id,
                                message_id = message.id
                            }
                        }
                        if tbl then
                            for i,v in pairs(tbl) do
                                t[i] = v
                            end
                        end
                        local res = self:Request({
                            Url = SynDiscord.API_PROXY .. string.format('channels/%s/messages', message.channel_id),
                            Method = 'POST',
                            Headers = {
                                ['Content-Type'] = 'application/json'  
                            },
                            Body = SynDiscord.Utils:JSONEncode(t)
                        })
                        return res.Body
                    end
                end

                local Listeners = self.__meta__.EventListeners[Event]
                if Listeners then
                    for i,v in pairs(Listeners) do
                        pcall(v, parsed.Data)
                    end
                end
            end
        end)

        spawn(function() -- needed to keep the websocket client alive. so it doesnt just shut down after 30 seconds or so
            while wait(5) do
                client:Send(SynDiscord.Utils:JSONEncode({
                    Action = "Keep-Alive"
                }))
            end
        end)
    end
end

do -- Util Functions
    function SynDiscord.Utils:JSONDecode(JSON)
        return game:GetService("HttpService"):JSONDecode(JSON)
    end

    function SynDiscord.Utils:JSONEncode(Tbl)
        return game:GetService("HttpService"):JSONEncode(Tbl)
    end
    
    function SynDiscord.Utils:ConcatTables(Tbl1, Tbl2)
        if Tbl2 == nil or typeof(Tbl2) ~= 'table' then
            return false
        elseif Tbl1 == nil or typeof(Tbl1) ~= 'table' then
            return false
        end
        for i,v in pairs(Tbl2) do
            Tbl1[i] = v
        end
        return true
    end

    function SynDiscord.Utils:SnakeToCamelCase(snake_case) -- used for event names, ex: message_created -> messageCreated
        local res = string.gsub(snake_case, "_(%w+)", function(s)
            return string.upper(string.sub(s, 1, 1)) .. string.sub(s,2)
        end)
        return res 
    end
end

do
    SynDiscord.Embeds.__index = SynDiscord.Embeds

    function SynDiscord.Embeds.Create()
        return setmetatable({}, SynDiscord.Embeds)
    end

    function SynDiscord.Embeds:setFields(fields)
        --[[
            { 
                { inline = true, name = "NAME", value = "VALUE" }, 
                { inline = true, name = "NAME2", value = "VALUE2" }, 
                ... 
            }
        ]]
        if typeof(fields) ~= 'table' then
            error(string.format('SetFields expects a table. Received %s.', typeof(fields)))
            return self
        end
        
        self.fields = fields

        return self
    end

    function SynDiscord.Embeds:setTitle(title)
        self.title = tostring(title)
        return self
    end

    function SynDiscord.Embeds:setColor(hex)
        self.color = hex
        return self
    end

    function SynDiscord.Embeds:setThumbnail(url)
        self.thumbnail = {
            url = tostring(url)
        }
        return self
    end

    function SynDiscord.Embeds:setImage(url)
        self.image = {
            url = tostring(url)
        }
        return self
    end

    function SynDiscord.Embeds:setFooter(text, iconUrl)
        self.footer = {
            text = text,
            icon_url = iconUrl
        }
        return self
    end

    function SynDiscord.Embeds:setUrl(url)
        self.url = tostring(url)
        return self
    end

    function SynDiscord.Embeds:setDescription(description)
        self.description = tostring(description)
        return self
    end

    function SynDiscord.Embeds:setAuthor(name, url, iconUrl)
        self.author = {
            name = tostring(name),
            url = tostring(url),
            icon_url = tostring(iconUrl)
        }
        return self
    end
end

return SynDiscord
