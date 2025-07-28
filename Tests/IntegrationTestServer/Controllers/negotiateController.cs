// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

#if USE_AZURE_SIGNALR
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.SignalR.Management;

namespace NegotiationServer.Controllers
{
    [ApiController]
    public class NegotiateController : ControllerBase
    {
        private const string EnableDetailedErrors = "EnableDetailedErrors";
        private readonly ServiceHubContext _testHubContext;
        private readonly bool _enableDetailedErrors;

        public NegotiateController(ServiceHubContext testHubContext, IConfiguration configuration)
        {
            _testHubContext = testHubContext;
            _enableDetailedErrors = configuration.GetValue(EnableDetailedErrors, false);
        }

        [HttpPost("test/negotiate")]
        public Task<ActionResult> TestHubNegotiate(string user)
        {
            return NegotiateBase(user, _testHubContext);
        }

        private async Task<ActionResult> NegotiateBase(string user, ServiceHubContext serviceHubContext)
        {
            if (string.IsNullOrEmpty(user))
            {
                return BadRequest("User ID is null or empty.");
            }

            var negotiateResponse = await serviceHubContext.NegotiateAsync(new()
            {
                UserId = user,
                EnableDetailedErrors = _enableDetailedErrors
            });

            return new JsonResult(new Dictionary<string, string>()
            {
                { "url", negotiateResponse.Url },
                { "accessToken", negotiateResponse.AccessToken }
            });
        }
    }
}
#endif