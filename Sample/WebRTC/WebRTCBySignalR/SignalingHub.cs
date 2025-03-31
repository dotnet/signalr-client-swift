using Microsoft.AspNetCore.SignalR;

namespace WebRTCBySignalR;

public class SignalingHub : Hub
{
    public string? CurrentUser => (string?)Context.GetHttpContext()?.Request.Query["username"];

    public override async Task OnConnectedAsync()
    {
        var user = CurrentUser;
        if (string.IsNullOrEmpty(user))
        {
            Context.Abort();
            return;
        }
        await Groups.AddToGroupAsync(Context.ConnectionId, user, default);
        await Clients.All.SendAsync("UserConnected", user);
        await base.OnConnectedAsync();
    }

    public async Task Online(string remoteUser)
    {
        var user = CurrentUser;
        await Clients.Group(remoteUser).SendAsync("UserConnected", user);
    }

    public async Task SendMessage(string user, string message)
    {
        await Clients.Group(user).SendAsync("ReceiveMessage", CurrentUser, message);
    }

    public async Task Hangup(string user)
    {
        await Clients.Group(user).SendAsync("ReceiveMessage", CurrentUser, """{ "type": "hangup" }""");
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var user = CurrentUser;
        if (!string.IsNullOrEmpty(user))
        {
            await Clients.All.SendAsync("UserDisconnected", user);
        }
        await base.OnDisconnectedAsync(exception);
    }
}
