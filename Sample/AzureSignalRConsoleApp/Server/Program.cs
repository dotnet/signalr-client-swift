using ChatAppServer;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSignalR().AddAzureSignalR();

var app = builder.Build();

app.UseRouting();
app.MapHub<Chat>("/chat");
app.Run();
