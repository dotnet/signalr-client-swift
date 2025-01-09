using Microsoft.AspNetCore.SignalR;

namespace IntegrationTest.Hubs;

public class TestHub : Hub
{
    public async Task Echo(string user, string message)
        => await Clients.Client(Context.ConnectionId).SendAsync("EchoBack", user, message);
}