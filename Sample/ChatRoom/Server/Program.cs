using ChatAppServer;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSignalR();

var app = builder.Build();

app.UseRouting();
app.MapHub<Chat>("/chat");
app.Run();
