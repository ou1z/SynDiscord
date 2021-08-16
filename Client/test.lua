local SynDiscord = require('module.lua')
local Client = SynDiscord.Client.new()

Client:on('ready', function()
    print('bot is ready')
end)

Client:on('messageCreate', function(message)
    print(string.format('%s => %s', message.author.tag, message.content))
end)

Client:login('TOKEN')