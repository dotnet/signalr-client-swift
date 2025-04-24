using System.Runtime.CompilerServices;
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

    public async Task invokeWithEmptyClientResult(string message1)
    {
        Console.WriteLine("ClientResult invoking");
        var rst = await Clients.Client(Context.ConnectionId).InvokeAsync<object>("ClientResult", message1, CancellationToken.None);
        Console.WriteLine("ClientResult invoked");
        Console.WriteLine(rst);
        await Clients.Client(Context.ConnectionId).SendAsync("EchoBack", "received");
    }
    
    public async Task<int> AddNumbers(int basic, IAsyncEnumerable<int> stream)
    {
        int sum = basic;
        await foreach (var number in stream)
        {
                sum += number;
                Console.WriteLine(sum);
        }
        return sum;
    }
    
    public async IAsyncEnumerable<int> Count(int basic, IAsyncEnumerable<int> stream)
    {
        int counter = basic;
        await foreach (var number in stream)
        {
            counter ++;
            Console.WriteLine(counter);
            yield return counter;
        }
    }

    public async IAsyncEnumerable<string> Stream()
    {
        yield return "a";
        yield return "b";
        yield return "c";
    }
        
}