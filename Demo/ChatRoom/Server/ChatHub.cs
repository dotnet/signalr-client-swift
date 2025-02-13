// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using Microsoft.AspNetCore.SignalR;

namespace ChatAppServer;

public class Chat: Hub
{
    public async Task Broadcast(string userName, string message)
    {
        await Clients.All.SendAsync("message", userName, message);
    }
}