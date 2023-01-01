# JustLogsPlease

This solution optimises download time of Microsoft 365's Unified Audit Log and allows you to resume downloads without losing data, which is very useful for large collections. Simply run `.\collect.ps1` to start a collection.                                                                                

## Why is this repo different?

Microsoft imposes several limitations on external record collection, including:

- Makings logs older than 7 days not accessible through their Management API
- Imposing a limit of the number of records you can download in a single session
- Using rate-limiting / throttling to slow requests

Other solutions have attempted to resolve these issues primarily by allowing the user to specify a time collection period, for e.g., 1 hour. They then scroll through the records in chunks, hoping that no single collection point exceeds the maximum limits allowed by Microsoft. If the connection is dropped, times out, or fails due to Microsoft's rate limiting, then you lose data and have to start again. 

In many cases, you may never be able to complete a full tenant-wide collection or have confidence that you have collected all the available data.

In comparison, this solution resolves these issues by:

- **Automatically calculating appropriate time periods for collection.** This ensures that no chunk will ever exceed Microsoft's limits and highly optimises download time by accommodating larger time periods where there are fewer logs and therefore avoiding the harshest rate-limiting restrictions.

- **Allowing you to resume collections without losing data.** This means if a collection fails, you can cancel the script and retry it later or from a new IP (to sidestep rate-limiting), without having to start the entire collection over again.

- **Providing a high level of assurance that all available logs have been collected.** This is because each time chunk has identified the number of logs it should contain before collection, so you are able to validate that expected data == collected data.

If you're interested in a more detailed explanation on why these features were necessary and how they were implemented, you can read more here.

## How to use

To run **JustLogsPlease**, clone this repository and run the following commands in PowerShell:

``` powershell
 .\collect.ps1
```

You'll immediately be asked to authenticate into your Office365 tenant, and a 90-day collection will begin automatically. Below  is some information on the parameters you can use to customise your collection.

| Parameter       | Description                                                                                                                                                                                                                                                                             |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| -StartDate      | A string containing the date that you would like to start collection from, e.g., '23/01/2020 05:34:33' or '05/02/2020'. The datetime format will default to the settings on your computer, so unless you are based in North America, you should be able to use the `dd/MM/yyyy` format. |
| -EndDate        | A string containing the date that you would like to end the collection, e.g., '23/01/2020 05:34:33' or '05/02/2020'.                                                                                                                                                                    |
| -Lookback       | If you don't want to use dates, simply enter a number indicating the days you want to look back on, starting from today, e.g., a value of 10 will start collection from midnight 10 days ago. This defaults to 90 days if StartDate and EndDate are not specificed.                     |
| -Resume         | A flag that instructs the collection to resume a partially completed collection.                                                                                                                                                                                                        |
| -Cert | If you are authenticating via an Azure App Registration (refer here for commentary), provide the thumbprint of the certificate authenticating your connection. Not required if you are signing in as a user.                                                                            |
| -AppID          | The AppID of the Azure Application you are authenticating against.                                                                                                                                                                                                                      |
| -Org   | Name of your tenant hosting your Azure Application, i,e., x6my8.onmicrosoft.com     