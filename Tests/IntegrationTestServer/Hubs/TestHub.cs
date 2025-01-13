using Microsoft.AspNetCore.SignalR;

namespace IntegrationTest.Hubs;

public class TestHub : Hub
{
    public async Task Echo(string message1, object message2)
        => await Clients.Client(Context.ConnectionId).SendAsync("EchoBack", message1, message2);
    
    public object Invoke(string message1, object message2) => message2;

    public async IAsyncEnumerable<string> Stream()
    {
        yield return "a";
        yield return "b";
        yield return "c";
    }
        
}