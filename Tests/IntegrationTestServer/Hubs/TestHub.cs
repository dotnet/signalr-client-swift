using Microsoft.AspNetCore.SignalR;

namespace IntegrationTest.Hubs;

public class TestHub : Hub
{
    public async Task Echo(string message1, object message2)
        => await Clients.Client(Context.ConnectionId).SendAsync("EchoBack", message1, message2);
    
    public object Invoke(string message1, object message2) => message2;

    public void InvokeWithoutReturn(string message1)
    {
    }

    public async Task InvokeWithClientResult(string message1)
    {
        var result = await Clients.Client(Context.ConnectionId).InvokeAsync<string>("ClientResult", message1, CancellationToken.None);
        await Clients.Client(Context.ConnectionId).SendAsync("EchoBack", result);
    }

    public async IAsyncEnumerable<string> Stream()
    {
        yield return "a";
        yield return "b";
        yield return "c";
    }
        
}