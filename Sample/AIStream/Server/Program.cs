using AIStreaming;
using AIStreaming.Hubs;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddSignalR();
builder.Services.AddSingleton<GroupAccessor>()
    .AddSingleton<GroupHistoryStore>()
    .AddAzureOpenAI(builder.Configuration);

var app = builder.Build();

app.UseRouting();

app.MapHub<GroupChatHub>("/groupChat");
app.Run();
