using Microsoft.AspNetCore.SignalR;

namespace ChatAppServer;

public class Chat: Hub
{
    public async Task Broadcast(string userName, string message)
    {
        await Clients.All.SendAsync("message", userName, message);
    }
}