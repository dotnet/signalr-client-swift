using WebRTCBySignalR;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.

builder.Services.AddControllers();
builder.Services.AddSignalR();

var app = builder.Build();

// Configure the HTTP request pipeline.

app.UseAuthorization();

app.UseRouting();
app.MapHub<SignalingHub>("/signalingHub");
app.UseStaticFiles();

app.Run();
