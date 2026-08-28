using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Options;
using OpenAI;
using System.Text;

namespace AIStreaming.Hubs
{
    public class GroupChatHub : Hub
    {
        private readonly GroupAccessor _groupAccessor;
        private readonly GroupHistoryStore _history;
        private readonly OpenAIClient _openAI;
        private readonly OpenAIOptions _options;

        public GroupChatHub(GroupAccessor groupAccessor, GroupHistoryStore history, OpenAIClient openAI, IOptions<OpenAIOptions> options)
        {
            _groupAccessor = groupAccessor ?? throw new ArgumentNullException(nameof(groupAccessor));
            _history = history ?? throw new ArgumentNullException(nameof(history));
            _openAI = openAI ?? throw new ArgumentNullException(nameof(openAI));
            _options = options?.Value ?? throw new ArgumentNullException(nameof(options));
        }

        public async Task JoinGroup(string groupName)
        {
            ValidateGroupName(groupName);

            if (_groupAccessor.TryGetGroup(Context.ConnectionId, out var previousGroupName) &&
                previousGroupName is not null && previousGroupName != groupName)
            {
                await Groups.RemoveFromGroupAsync(Context.ConnectionId, previousGroupName);
            }

            await Groups.AddToGroupAsync(Context.ConnectionId, groupName);
            _groupAccessor.Join(Context.ConnectionId, groupName);
        }

        public override Task OnDisconnectedAsync(Exception? exception)
        {
            _groupAccessor.Leave(Context.ConnectionId);
            return Task.CompletedTask;
        }

        public async Task Chat(string userName, string message)
        {
            ValidateUserName(userName);
            ValidateMessage(message);

            if (!_groupAccessor.TryGetGroup(Context.ConnectionId, out var groupName))
            {
                throw new InvalidOperationException("Not in a group.");
            }

            if (groupName is null)
            {
                throw new InvalidOperationException("The group name is invalid.");
            }

            if (message.StartsWith("@gpt"))
            {
                var id = Guid.NewGuid().ToString();
                var actualMessage = message.Substring(4).Trim();
                if (string.IsNullOrWhiteSpace(actualMessage))
                {
                    throw new HubException("The @gpt command must include a message.");
                }

                var messagesIncludeHistory = _history.GetOrAddGroupHistory(groupName, userName, actualMessage);
                await Clients.OthersInGroup(groupName).SendAsync("NewMessage", userName, message);

                var chatClient = _openAI.GetChatClient(_options.Model);
                var totalCompletion = new StringBuilder();
                var lastSentTokenLength = 0;
                await foreach (var completion in chatClient.CompleteChatStreamingAsync(messagesIncludeHistory))
                {
                    foreach (var content in completion.ContentUpdate)
                    {
                        var remainingLength = GroupHistoryStore.MaxMessageLength - totalCompletion.Length;
                        if (remainingLength == 0)
                        {
                            break;
                        }

                        var contentText = content.Text ?? string.Empty;
                        totalCompletion.Append(contentText.Length <= remainingLength
                            ? contentText
                            : contentText[..remainingLength]);
                        if (totalCompletion.Length - lastSentTokenLength > 20)
                        {
                            await Clients.Group(groupName).SendAsync("newMessageWithId", "ChatGPT", id, totalCompletion.ToString());
                            lastSentTokenLength = totalCompletion.Length;
                        }
                    }

                    if (totalCompletion.Length == GroupHistoryStore.MaxMessageLength)
                    {
                        break;
                    }
                }
                _history.UpdateGroupHistoryForAssistant(groupName, totalCompletion.ToString());
                await Clients.Group(groupName).SendAsync("newMessageWithId", "ChatGPT", id, totalCompletion.ToString());
            }
            else
            {
                _history.GetOrAddGroupHistory(groupName, userName, message);
                await Clients.OthersInGroup(groupName).SendAsync("NewMessage", userName, message);
            }
        }

        private static void ValidateGroupName(string groupName)
        {
            if (string.IsNullOrWhiteSpace(groupName) || groupName.Length > GroupHistoryStore.MaxGroupNameLength)
            {
                throw new HubException($"Group name must be between 1 and {GroupHistoryStore.MaxGroupNameLength} characters.");
            }
        }

        private static void ValidateUserName(string userName)
        {
            if (string.IsNullOrWhiteSpace(userName) || userName.Length > GroupHistoryStore.MaxUserNameLength)
            {
                throw new HubException($"User name must be between 1 and {GroupHistoryStore.MaxUserNameLength} characters.");
            }
        }

        private static void ValidateMessage(string message)
        {
            if (string.IsNullOrWhiteSpace(message) || message.Length > GroupHistoryStore.MaxMessageLength)
            {
                throw new HubException($"Message must be between 1 and {GroupHistoryStore.MaxMessageLength} characters.");
            }
        }
    }
}
