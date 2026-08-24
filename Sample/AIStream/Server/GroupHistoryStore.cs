using OpenAI.Chat;

namespace AIStreaming
{
    public class GroupHistoryStore
    {
        public const int MaxGroups = 1_000;
        public const int MaxMessagesPerGroup = 100;
        public const int MaxGroupNameLength = 256;
        public const int MaxUserNameLength = 100;
        public const int MaxMessageLength = 4_096;

        private readonly Dictionary<string, List<ChatMessage>> _store = new();
        private readonly object _lock = new();

        public IReadOnlyList<ChatMessage> GetOrAddGroupHistory(string groupName, string userName, string message)
        {
            ValidateInput(groupName, userName, message);

            lock (_lock)
            {
                if (!_store.TryGetValue(groupName, out var chatMessages))
                {
                    if (_store.Count >= MaxGroups)
                    {
                        throw new InvalidOperationException("The maximum number of group histories has been reached.");
                    }

                    chatMessages = InitiateChatMessages();
                    _store.Add(groupName, chatMessages);
                }

                chatMessages.Add(new UserChatMessage(GenerateUserChatMessage(userName, message)));
                TrimHistory(chatMessages);
                return chatMessages.ToArray();
            }
        }

        public void UpdateGroupHistoryForAssistant(string groupName, string message)
        {
            ValidateInput(groupName, "assistant", message);

            lock (_lock)
            {
                if (!_store.TryGetValue(groupName, out var chatMessages))
                {
                    if (_store.Count >= MaxGroups)
                    {
                        throw new InvalidOperationException("The maximum number of group histories has been reached.");
                    }

                    chatMessages = InitiateChatMessages();
                    _store.Add(groupName, chatMessages);
                }

                chatMessages.Add(new AssistantChatMessage(message));
                TrimHistory(chatMessages);
            }
        }

        private static void TrimHistory(List<ChatMessage> chatMessages)
        {
            var messagesToRemove = chatMessages.Count - MaxMessagesPerGroup;
            if (messagesToRemove > 0)
            {
                chatMessages.RemoveRange(1, messagesToRemove);
            }
        }

        private static void ValidateInput(string groupName, string userName, string message)
        {
            if (string.IsNullOrWhiteSpace(groupName) || groupName.Length > MaxGroupNameLength)
            {
                throw new ArgumentException($"Group name must be between 1 and {MaxGroupNameLength} characters.", nameof(groupName));
            }

            if (string.IsNullOrWhiteSpace(userName) || userName.Length > MaxUserNameLength)
            {
                throw new ArgumentException($"User name must be between 1 and {MaxUserNameLength} characters.", nameof(userName));
            }

            if (string.IsNullOrWhiteSpace(message) || message.Length > MaxMessageLength)
            {
                throw new ArgumentException($"Message must be between 1 and {MaxMessageLength} characters.", nameof(message));
            }
        }

        private List<ChatMessage> InitiateChatMessages()
        {
            var messages = new List<ChatMessage>
            {
                new SystemChatMessage("You are a friendly and knowledgeable assistant participating in a group discussion." +
                " Your role is to provide helpful, accurate, and concise information when addressed." +
                " Maintain a respectful tone, ensure your responses are clear and relevant to the group's ongoing conversation, and assist in facilitating productive discussions." +
                " Messages from users will be in the format 'UserName: chat messages'." +
                " Pay attention to the 'UserName' to understand who is speaking and tailor your responses accordingly."),
            };
            return messages;
        }

        private string GenerateUserChatMessage(string userName, string message)
        {
            return $"{userName}: {message}";
        }
    }
}
