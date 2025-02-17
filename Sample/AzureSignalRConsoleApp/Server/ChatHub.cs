using Microsoft.AspNetCore.SignalR;

namespace ChatAppServer;

public class Chat: Hub
{
    public async Task Echo(string message)
    {
        await Clients.Caller.SendAsync("ReceiveMessage", message);
    }
}