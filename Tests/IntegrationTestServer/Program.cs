// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using IntegrationTest.Hubs;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSignalR().AddMessagePackProtocol();
var app = builder.Build();

app.UseRouting();
app.MapHub<TestHub>("/test");

app.Run();