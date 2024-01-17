# SwiftOpenAIProxy

## Configuring SwiftOpenAIProxy

SwiftOpenAIProxy can be customized using a combination of arguments and environment variables. Both can be edited in Xcode using the Target -> Edit scheme.

![Xcode screenshot of edit scheme menu](Images/EditScheme.png)

### Arguments passed on launch

| Argument | Default value | Default in scheme |
| --- | --- | --- |
| --hostname | 0.0.0.0 | |
| --port | 443 | 8081
| --target | https://api.openai.com | |

### Environment variables

#### OpenAI environment variables. 
| Variable | Description | reference |
| --- | --- | --- |
| OpenAI-APIKey | OpenAI API key (sk-...) | https://platform.openai.com |
| OpenAI-Organization | OpenAI org identifier (org-...) | https://platform.openai.com |
| allowKeyPassthrough | if 1, requests with a valid OpenAI key and org in the header will be forwarded to OpenAI without modifications |

#### App Store Connect environment variables
| Variable | Description | reference |
| --- | --- | --- |
| appTeamId | Apple Team ID | https://appstoreconnect.apple.com/ |
| appBundleId | E.g. com.example.myapp | https://appstoreconnect.apple.com/ |
| appAppleId | Apple Id under App Information -> General Information | https://appstoreconnect.apple.com/ |

#### App Store Server API environment variables
| Variable | Description | reference |
| --- | --- | --- |
| IAPPrivateKey | IAP private key | https://appstoreconnect.apple.com/access/api/subs |
| IAPIssuerId | IAP Issuer Id | https://appstoreconnect.apple.com/access/api/subs |
| IAPKeyId | IAP Key Id | https://appstoreconnect.apple.com/access/api/subs |

#### JWT environment variables
| Variable | Description | reference |
| --- | --- | --- |
| JWTPrivateKey |  | https://jwt.io/introduction |

To create a new JWT private key, use the folllowing command in macOS Terminal `openssl rand -base64 32` and copy the result into the environment variable. The key look something like `8TiUFcwQsoVJVrUuG7GG79E57woe4h3wKM2qC4tX7eQ=`


