# GSuite Reports Channeler

Lightweight serverless pipeline, leveraging AWS Lambda and Step Functions,
to collect Google Workspace Admin Report logs via [Push Notifications](https://developers.google.com/admin-sdk/reports/v1/guides/push).

This module creates infrastructure to handle the following:
1. Create [notification channels](https://developers.google.com/admin-sdk/reports/v1/guides/push#creating-notification-channels) for specified [applications](https://developers.google.com/admin-sdk/reports/reference/rest/v1/activities/watch#ApplicationName)
2. Auto-renew channels as they reach their expiration time

See the [Details](#details) section below for a better understanding of how this works.

## Setup - Google

1. Ensure [these prerequisites](https://developers.google.com/admin-sdk/reports/v1/guides/prerequisites) are met
2. Create Google service account credentials that use domain-wide delegation by following [these instructions](https://developers.google.com/admin-sdk/reports/v1/guides/delegation).
2. Download the service account credentials as a JSON file (JWT) that can be more easily
used with the Google API client library (**note: do not download in P12 format**).

## Setup - AWS

1. Create a new secret in [AWS Secrets Manager](https://us-east-1.console.aws.amazon.com/secretsmanager/newsecret?region=us-east-1)
with the contents of the JWT file that was downloaded in above setup.
    * Choose "Other type of secret"
    * Under "Key/value pairs", choose "Plaintext"
    * Copy JSON file content downloaded in # 2 above and paste the value into the form
    * (optional) Choose existing encryption key for the secret or create a new one
    * Follow prompts and save secret with desired name and **make note of the name used**

## Usage

```hcl
module "channeler" {
  source = "ryandeivert/gsuite-reports-channeler/aws"

  delegation_email = "svc-acct-email@domain.com"
  secret_name      = "google-reports-jwt" # name of secret from setup above
  applications     = ["drive", "admin", "calendar", "token"]
}
```

## Optional Athena Submodule

The `modules/athena` directory contains the necessary components to make the logs
from this module searchable.

## Examples

See the `examples` directory for a end-to-end implementation of this module and the
optional athena submodule.

## Details

This module uses a number of serverless AWS services to make channel renewing possible.
The overall process looks something like:

1. Terraform apply creates infrastructure, including:
    * 2 Lambda functions: one for renewing channels, and one the act as an HTTPS endpoint
    * Step Function with the main purpose of "waiting" for channel expiration
2. As part of the Terraform apply process, the `channel_renewer` Lambda is invoked with some
basic metadata (eg: `application`).
3. The **first** invocation of the `channel_renewer` opens the first channel and immediately
executes the Step Function with the necessary channel metadata.
    * A separate Step Function execution occurs for _each_ app specified.
4. Each Step Function execution goes immediately into a ["Wait"](https://docs.aws.amazon.com/step-functions/latest/dg/amazon-states-language-wait-state.html) state, which dynamically waits until the specified number of
minutes before channel expiration to continue (default: 15 minutes).
    * Note: channels have a maximum lifespan of [21600 seconds](https://developers.google.com/admin-sdk/reports/v1/guides/push#optional-properties) (6 hours)
5. As the channel is about to expire, the Step Function invokes the `channel_renewer` function
again, passing in the channel metadata from the previous execution.
6. The `channel_renewer` will create a new channel, and subsequently stop the old channel using
the channel metadata passed to the function by the Step Function. The new channel metadata is
returned to the Step Function execution.
7. The existing Step Function execution receives the new channel metadata, and starts another
execution of the Step Function with this new input.
8. Steps 4-7 above repeat until otherwise interrupted (eg: manually stopped).

## Caveats

### Duplicate Records

The renewal of channels happens before old channels are "stopped". This is by design and
is intended to ensure there is no gaps in data received. However, as a result of this,
there may be a small amount of data sent to both active channels that exist alongside each
other for the minuscule duration of time the passes before the old channel is stopped.

Therefore, it is best to perform deduplication of records on the consumer side (eg: via SQL query).

Some potential solutions could be:
* Switch to FIFO SNS Topic and use [message deduplication](https://docs.aws.amazon.com/sns/latest/dg/fifo-message-dedup.html)
  * A FIFO topic is not used now because it is unlikely to handle the required throughput.
  [300 messages per second](https://docs.aws.amazon.com/general/latest/gr/sns.html) is the maximum
  throughput at the time of writing.
* suggestions welcome!

### Removing an "application"

As part of the normal operating process, new channels are created and old channels are
automatically and appropriately stopped in a perpetual cycle. The Step Function state
machine itself maintains the only reference to the state of the channel(s). This avoids
the need to store any state externally, and avoids the need to use any sort of cron-based
approach to handle renewal of channels.

Because of this, if you decided you would like to stop receiving events for a given application,
removing it from the list of `applications` will not suffice. Once the pipeline is active for a
specific application, the respective Step Function execution for the application(s) that you would
like to stop receiving events for will have to be stopped manually.

The Step Function execution IDs are prefixed with the application name, followed by a UUID. For
example, a Step Function execution handling the `admin` application will look something like:
`admin_bd003813-4857-489a-8dfc-4502aed85988`. The UUID is the ID of the currently active channel.

Note that since channels themselves have a maximum lifespan of [21600 seconds](https://developers.google.com/admin-sdk/reports/v1/guides/push#optional-properties) (6 hours), you can either let the channel die organically or manually
stop it using the API.
