# Pico AI Proxy

### Introduction

Pico AI Proxy is a reverse proxy created specifically for iOS, macOS, iPadOS, and VisionOS developers.

Pico AI Proxy was previously called SwiftOpenAIProxy.  

### Highlights

- Prevents hackers from stealing your API keys
- Makes sure every user has a in-app subscription by validating App Store store receipts using Apple's [App Store Server Library](https://github.com/apple/app-store-server-library-swift)
- Accepts the standard OpenAI Chat API your chat app already uses, so no changes need to be made to your client app 
- Supports multiple LLM providers such as OpenAI and Anthropic (more to come, stay tuned). PicoProxy automatically converts OpenAI Chat API calls to the different providers
- One click install on [Railway](https://railway.app) and can be installed manually on many other hosting providers. [See How to Deploy](#How-to-deploy)

PicoProxy is written in server-side Swift and uses [HummingBird](https://github.com/hummingbird-project/hummingbird) for its HTTP-server.
  
### Background

In December 2023, I faced a [significant hack](https://youtu.be/_ueiYhLwwBc?si=8UC_7VZOrhgcXoKV) when my OpenAI key was compromised. They quickly used up my entire $2,500 monthly limit, resulting in an unexpected bill from OpenAI. This incident also forced me to take my app, Pico, offline, causing me to miss the lucrative Christmas sales period.  

As a response to this incident, I developed Pico AI Server, the first OpenAI proxy created in Server-side Swift. This tool is especially convenient for Swift developers, as it allows easy customization to meet their specific requirements.

Pico AI Proxy is designed to be compatible with any existing OpenAI library. It works seamlessly with libraries such as [CleverBird](https://github.com/btfranklin/CleverBird), [OpenAISwift](https://github.com/adamrushy/OpenAISwift), [OpenAI-Kit](https://github.com/dylanshine/openai-kit), [MacPaw OpenAI](https://github.com/MacPaw/OpenAI), and can also integrate with your custom code.

### Key features

- Pico AI Proxy uses Apple's [App Store Server Library](https://github.com/apple/app-store-server-library-swift) for receipt validation
- Once the receipt is validated, Pico AI Proxy issues a JWT token the client can use for subsequent calls
- Pico AI Proxy is API agnostic and forwards any request to https://api.openai.com.
- The forwarding endpoint is customizable, allowing redirection to various non-OpenAI API endpoints
- Optionally forward calls with a valid OpenAI key and org without validation
- Pico AI Server can optionally track individual users through App Account IDs. This requires the client app to send a unique UUID to the [purchase](https://developer.apple.com/documentation/storekit/product/3791971-purchase) method.

### Supported APIs

| API | Chat async | Chat streaming | Embeddings | Audio | Images |
| --- | --- | --- | --- | --- | --- |
| [OpenAI](https://platform.openai.com/docs/models) | ✅ | ✅ | ✅ | ✅ | ✅ |
| [Anthropic](https://docs.anthropic.com/claude/docs/) | ❌ | ✅ | ❌ | ❌ | ❌ |

### Supported Models and endpoints

OpenAI:

- Pico AI Proxy supports all OpenAI models and endpoints: `chat`, `audio`, `embeddings`, `fine-tune`, `image`

Anthropic: 

- API version `2023-06-01`
- `claude-3-opus-20240229`
- `claude-3-sonnet-20240229`
- `claude-3-haiku-20240307`


### What's implemented
- [x] Reverse proxy server forwarding calls to OpenAI (or any other endpoint)
- [x] Authenticates using App Store receipt validation
- [x] Rate limiter and black list
- [x] Automatically translate and forward traffic to other AI APIs based on model setting in API call
- [ ] [App Attestation](https://developer.apple.com/documentation/devicecheck/preparing_to_use_the_app_attest_service) is on hold, as macOS doesn't support app attestation
- [ ] Account management

## Requirements

- [Apple Developer Account](https://developer.apple.com)
- [OpenAI API key](https://openai.com/blog/openai-api)
- [Anthropic API key](https://docs.anthropic.com/claude/reference/getting-started-with-the-api)

## How to Set Up Pico AI Proxy

To set up Pico AI Proxy, you need:
- Your OpenAI API key and organization
- A JWT private key, which can be generated in the terminal
- Your app bundle Id, Apple app Id and team Id
- App Store Server API key, Issuer Id, and Key Id
- Apple root certificates, which are included in the repository but should be updated if Apple updates their certificates

#### OpenAI API key and organization
Generate an OpenAI API key at https://platform.openai.com

#### JWT Private key
Create a new JWT private key in macOS Terminal using `openssl rand -base64 32`

Note: This JWT token is used to authenticate your client app. It is a different JWT token the App Store Server Library uses to communicate with the Apple App Store API.

#### App Ids
Find your App bundle Id, Apple app Id, and team Id on https://appstoreconnect.apple.com/apps Under **App Information** in the **General** section, you will find these details.

Team Id is a 10-character string and can be found in https://developer.apple.com/account under **Membership Details**.

#### App Store Server API key
Generate the key under the **Users and Access** tab in App Store Connect, specifically under **In-app Purchase** [here](https://appstoreconnect.apple.com/access/api/subs). You will also find the Issuer Id and Key Id on the same page.

See for more details [Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api)

## Run Pico AI Proxy from Xcode

To run Pico AI Proxy from Xcode, set the environment variables and arguments listed below to the information listed in How to Set Up Pico AI Proxy

Both environment variables and arguments can be edited in Xcode using the Target -> Edit scheme.

![Xcode screenshot of edit scheme menu](Images/EditScheme.png)

### Arguments passed on launch

| Argument | Default value | Default in scheme |
| --- | --- | --- |
| --hostname | 0.0.0.0 | |
| --port | 8080 | 8080 |
| --target | https://api.openai.com | |

When launched from Xcode, Pico AI Proxy is accessible at http://localhost:8080. When deployed on Railway, Pico AI Proxy will default to port 443 (https). 

All traffic will be forwarded to `target`. The 'target' can be modified to direct traffic to any API, regardless of whether it conforms to the OpenAI API. , as long as your client application is compatible.
The target is the site where all traffic is forwarded to. You can change the target to any API, even if the API doesn't conform OpenAI (so long as your client app does).

## Environment variables

### LLM providers environment variables. 
| Variable | Description | reference |
| --- | --- | --- |
| OpenAI-APIKey | OpenAI API key (sk-...) | https://platform.openai.com |
| OpenAI-Organization | OpenAI org identifier (org-...) | https://platform.openai.com |
| Anthropic-APIKey | Anthropic API key (sk-ant-api3-...) | https://docs.anthropic.com/claude/docs/ |
| ~~allowKeyPassthrough~~ | if 1, requests with a valid OpenAI key and org in the header will be forwarded to OpenAI without modifications (depricated) |

### App Store Connect environment variables
| Variable | Description | reference |
| --- | --- | --- |
| appTeamId | Apple Team ID | https://appstoreconnect.apple.com/ |
| appBundleId | E.g. com.example.myapp | https://appstoreconnect.apple.com/ |
| appAppleId | Apple Id under App Information -> General Information | https://appstoreconnect.apple.com/ |

### App Store Server API environment variables
| Variable | Description | reference |
| --- | --- | --- |
| IAPPrivateKey | IAP private key | https://appstoreconnect.apple.com/access/api/subs |
| IAPIssuerId | IAP Issuer Id | https://appstoreconnect.apple.com/access/api/subs |
| IAPKeyId | IAP Key Id | https://appstoreconnect.apple.com/access/api/subs |

The `IAPPrivateKey` in Pico AI Proxy is formatted in PKCS #8, which is a multi-line format. The format begins with `-----BEGIN PRIVATE KEY-----` and ends with `-----END PRIVATE KEY-----`. Between these markers, the key comprises four lines of base64-encoded data. However, while Xcode supports environment variables with newlines, many hosting services, such as [Railway](https://railway.app), do not.

To ensure compatibility across different environments, Pico AI Proxy requires the private key to be condensed into a single line. This is achieved by replacing all newline characters with `\\n` (double backslash followed by `n`).

A correctly formatted `IAPPrivateKey` for Pico AI Proxy should appear as a single line: `-----BEGIN PRIVATE KEY-----\\n<LINE1>\\n<LINE2>\\n<LINE3>\\n<LINE4>\\n-----END PRIVATE KEY-----`, where `<LINE1>`, `<LINE2>`, `<LINE3>`, and `<LINE4>` represent the base64-encoded data of the key.

### JWT environment variables
| Variable | Description | reference |
| --- | --- | --- |
| JWTPrivateKey |  | https://jwt.io/introduction |

### Rate limiter environment variables
| Variable | Default value | Description | 
| --- | --- | --- |
| enableRateLimiter | 0 | Set to 1 to activate the rate limiter |
| userMinuteRateLimit | 15 | Max queries per minute per registered user
| userHourlyRateLimit | 50 | Max queries per hour per registered user
| userPermanentBlock | 50 | Blocked request threshold for permanent user ban
| anonMinuteRateLimit | 60 | Combined max queries per minute for all anonymous users
| anonHourlyRateLimit | 200 | Combined max queries per hour for all anonymous users
| anonPermanentBlock | 50 | Blocked request threshold for banning all anonymous users 

#### Guidelines and behavior

By default, the rate limiter is off. To activate, set `enableRateLimiter` to 1.

The rate limiter counts requests and doesn't distinguish between different models or LLM providers. It's primarily a safeguard against abusive traffic.

Users are identified by their app account tokens from the StoreKit 2 Transaction.purchase() call. Unidentified users are considered anonymous. For apps where all users are identified, consider removing the anonymous user limits (`anonHourlyRateLimit`, `anonMinuteRateLimit`, and `anonPermanentBlock`).

#### Rate limits

There are three rate levels that can be individually set or disabled:

- A maximum number queries per hour (`userMinuteRateLimit` and `anonHourlyRateLimit`)
- A maximum number of queries per minute (`userHourlyRateLimit` and `anonMinuteRateLimit`)
- A maximum number of blocked messages (`userPermanentBlock` and `anonPermanentBlock`)
 
If the 1 minute limit is reached, the user will be blocked for 5 minutes. If the hourly limit is reached, the user will be blocked for 60 minutes. If a user has exceeded the value set in `userPermanentBlock` or `anonPermanentBlock` they will be banned permanently. These values are hardcoded in Pico AI Proxy.

Note 
Pico AI Proxy currently does not persist data. Upon server restart, any permanently blocked users will be unblocked.

## How to call Pico AI Proxy from your iOS or macOS app

Using [CleverBird](http://github.com/btfranklin/CleverBird/issues)
```Swift
    import Get
    import CleverBird

    var token: Token? = nil

    func completion(prompt: String) async await {
        let openAIConnection = OpenAIAPIConnection(apiKey: token.token, organization: "", scheme: "http", host: "localhost", port: 8080)
        let chatThread = ChatThread()
            .addSystemMessage(content: "You are a helpful assistant.")
            .addUserMessage(content: "Who won the world series in 2020?")
        do {
            let completion = try await chatThread.complete(using: openAIAPIConnection)
        } catch CleverBird.proxyAuthenticationRequired {
            // Client needs to re-authenticate
            token = try await fetchToken()
            try await completion(prompt: String)
        } catch CleverBirdError.unauthorized {
            // Prompt user to buy a subscription          
        }      
    }
    
    func fetchToken() async throws -> Token {
        let body: String?

        /*
        // Fetch app store receipt
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: appStoreReceiptURL.path),
           let receiptData = try? Data(contentsOf: appStoreReceiptURL, options: .alwaysMapped) {
            body = receiptData.base64EncodedString(options: [])
        } else {
            // when running the app in Xcode Sandbox, there will be no receipt. In sandbox, Pico AI Proxy will accept
            // the receipt Id.
            body = "transaction Id here"
        }
        */
        
        // Validating receipts is temporary disabled 
        body = "transaction Id here"
        
        let tokenRequest = Request<Token>(
            path: "appstore",
            method: .post,
            body: body,
            headers: nil)
        let tokenResponse = try await AIClient.openAIAPIConnection.client.send(tokenRequest)
        return tokenResponse.value
    }

    struct Token: Codable {
        let token: String
    }
```

Optionally: Track users using [app account token](https://developer.apple.com/documentation/storekit/product/purchaseoption/3749440-appaccounttoken)
```Swift
 // Create new UUID
 let id = UUID()
 // Add id to user account

 // Purchase subscription
 let result = try await product.purchase(options: [.appAccountToken(idUUID)])
```

Pico AI Proxy will automatically extract the app account token from the receipts.

Pico AI Proxy may generate two distinct error codes related to authorization issues: unauthorized (401) and proxyAuthenticationRequired (407). The unauthorized error indicates a lack of a valid App Store subscription on the user's part. On the other hand, the proxyAuthenticationRequired error signifies that the client's authentication token is no longer valid, a situation that may arise following a server reboot. In the latter case, reauthorization can be achieved through a straightforward re-authentication process that does not require user intervention. 

## How to deploy

Use link below to deploy Pico AI Proxy on Railway. The link includes a referral code.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/ocPcV2?referralCode=WKPLp3)

Alternatively, Pico AI Proxy can be installed manually on any other hosting provider.

## Apps using Pico AI Proxy

- Pico


## Contributors
<a href="https://github.com/ronaldmannak/SwiftOpenAIProxy/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=ronaldmannak/SwiftOpenAIProxy" />
</a>
