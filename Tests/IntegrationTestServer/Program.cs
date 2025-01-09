using IntegrationTest.Hubs;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSignalR();
var app = builder.Build();

app.UseRouting();
app.MapHub<TestHub>("/test");

app.Run();