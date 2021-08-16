local SynDiscord = loadstring(game:HttpGet('https://raw.githubusercontent.com/ou1z/SynDiscord/main/Client/module.lua'))()
local Client = SynDiscord.Client.new()

Client:on('ready', function()
    print('bot is ready')
end)

Client:on('messageCreate', function(message)
    print(string.format('%s => %s', message.author.username, message.content))
end)

Client:login('TOKEN')
