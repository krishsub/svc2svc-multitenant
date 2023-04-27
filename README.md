# Cross-tenant Service-to-Service Communication using Azure AD authentication

## Description
There are scenarios when an application or service running in one Azure AD
tenant needs to communicate with an Azure service hosted in another Azure
AD tenant. A common use-case could be when you want to enable a partner or
customer of yours to exchange information with you (or the other way around).

An option discussed here is to use Azure AD authentication in order for an
application hosted in one Azure AD tenant to securely authenticate using
OAuth/OpenID Connect to an Azure service in another Azure AD tenant. This 
isn't about creating or exposing an API on top of that Azure service, but 
rather using the service's native connectivity options in order to directly
communicate with that service.

Almost all Azure services provide Azure AD authentication to securely
connect to an Azure service. However, most of these mechanisms and samples
illustrate how this access is set up and granted in the context of a single
tenant only.

In the context of this narrative and code samples, we refer to two Azure
AD instances to illustrate cross-tenant access:
1. `my-tenant.com` to refer to your own Azure AD tenant (shortcut to
`my-tenant.onmicrosoft.com`)
2. `partner-tenant.com` to refer to a customer or partner Azure AD tenant
(shortcut to `partner-tenant.onmicrosoft.com`) 

![][ImgGenericSvcMultitenant]

One possibility to enable this communication is to hand out the access key
or some set of credentials to your Azure service to your partner or customer.
For example, many Azure services like [Azure Storage][StorageSas],
[Event Hubs][EventHubsSas], [Service Bus][ServiceBusSas], etc. support using
Shared Access signatures (SAS). Other Azure Services like CosmosDB,
PostgreSQL, etc. support some form of key or username / password for
authentication and authorization. 

In a cross-tenant scenario, where the service is in one Azure AD tenant and
the application(s) that makes use of that service are in another Azure AD
tenant(s), it means there are at least two challenges from a security and
governance standpoint:

1. It becomes the responsibility of the Azure AD tenant (where the service
resides) to generate SAS tokens or keys, their lifetime, distribute them
to partners or customers, monitor their usage, revoke them if necessary,
etc.
2. Once distributed, you have no way of knowing how the partner or customer
is securing those tokens or keys and using them. Remember, those keys or
tokens are owned by you - i.e. you generate them and hand them out. 

*Side note:* There are mechanisms from a networking perspective in order
to further secure flows between 2 services in different (or same) tenants.
For example: Private Link, VNET Peering, Firewall/Filtering/Routing, etc.
However, these are at Layer 3 or Layer 4 and we are mostly concerned with
authentication & authorization flows that typically occur at the application
layer.

## Alternatives to SAS or keys
Since your customer or partner is also using Azure AD, two alternatives come
to mind:

1. [Managed Identities][ManagedIdentity]
2. [Azure AD Guest Accounts (B2B)][AADGuestUsers]

### Managed Identity
Managed identities [don't support cross-tenant access][CrossTenantNoNo].
In addition, it may be that the application runs in an non-Azure environment
(on-premises, other clouds, etc.) and while it may be able to leverage Azure
AD, it can't be assigned a managed identity.

### Azure AD Guest Accounts (B2B)
Azure AD Guest Account will enable you to use Azure [Role-Based Access Control
(RBAC)][RBAC] to authenticate and authorize users in another Azure AD tenant
to access Azure resources in your tenant. You could (for example), invite a
user "`Bob`" in a partner's Azure AD tenant (say `bob@partner-tenant.com`).
Since "`Bob`" is now a guest in your own Azure AD tenant (`my-tenant.com`),
you can add him to a security group which is then granted fine-grained access
on specific Azure resources in your Azure AD tenant.

This would permit "`Bob`" to authenticate against his own tenant
(`partner-tenant.com`), but access specific resources in your own tenant
(`my-tenant.com`) that you have granted him access using built-in or custom
roles.

This works well, and when "`Bob`" leaves his organization, or his account is
deleted or disabled for whatever reason, he automatically loses the ability
to access resources in your tenant (`my-tenant.com`) simply because he can't
authenticate anymore against his own tenant (`partner-tenant.com`).

While guest accounts work well for (human) user identities, what if an
application or service in your partner's tenant needs to be granted access
to an Azure service in your tenant? Guest accounts won't work in this case.

## Multi-tenant application registrations to the rescue
The concept of [multi-tenant application registrations][MultiTenantAppBasics]
has existed for a long time. 

The primary use-case (and some would say also the challenge) with multi-tenant
*applications* is that sign-ins are accepted from any Azure AD tenant. For 
example, if a web application leverages a multi-tenant application 
registration, then user signs are permitted from other Azure AD tenants. 
**This is by-design**. It is then up to the application itself to implement
any further authentication & authorization checks.

There are two important differences in the way we are using multi-tenant
applications in our scenario:

1. There is **no** web application in our scenario. This prevents sign-ins from
other tenants.
2. We instead rely on a very explicit way to grant (only) a specific partner's
application registration access to resources in your own tenant. In some ways,
it is the **inverse** of the way custom applications leverage multi-tenant app
registrations! 

> The above is not a commonly known use-case of multi-tenant application 
> registrations. They are typically used in web applications, but here we are
> leveraging them directly in our Azure services which may or may not use HTTPS
> for any protocol level communication (e.g. Kafka, AMQP, etc.).

Let's take an example of an Event Hub in your own tenant (`my-tenant.com`).
You'd like a parter of yours (`partner-tenant.com`) to have certain
applications send messages to your Event Hub secured using Azure AD tokens.

![][ImgEventHubs]

The high-level steps to achieve the above are:
1. Ensure that the partner creates a multi-tenant application registration on
their tenant (`partner-tenant.com`) and sends you (the tenant where the service
 resides - i.e. `my-tenant.com`) **only** its Client Id or Application Id. The
 Client Id or Application Id isn't a credential. It is simply an identifier.
 Just to be clear: if the partner uses certificates or secrets to ensure that
 their application can use that application registration securely, you don't
 need to know anything about it. All you need is the Client Id or Application
 Id.
 2. You will use that Client Id or Application Id from your partner's Azure AD
 tenant to create a service principal in your own tenant (`my-tenant.com`).
 The differences and relationships between an application object (application
 registration) and a service principal are
 [explained quite nicely here][AppObjVersusServicePrincipal].
 3. This service principal in your own own tenant (`my-tenant.com`) exists
 in your tenant only. It is a local representation of the application
 registration in your partner tenant (`partner-tenant.com`), but doesn't
 contain any credentials like secrets or certificates.
 4. This service principal will be granted the familiar Azure role-based
 resource access to specific resources in your own tenant.
 5. The application in the partner's Azure AD tenant will acquire a token
 with an important change: the Azure AD tenant they use will be yours instead
 of their own. That is, in the client credentials flow, where the partner
 application would normally specify their own Azure AD token endpoint (and
 client id, secret or certificate, etc.), the Azure AD token endpoint
 would be  your own to indicate that the token issuer is your own
 (`my-tenant.com`).
 6. This access token would be used by the partner application
 (running at `partner-tenant.com`) to access any service in your own tenant
 (`my-tenant.com`) where you have explicitly granted access in step 4 above.

 ## Details
 1. Ask your partner or customer to create a multi-tenant application
 registration in their tenant (`partner-tenant.com`) and provide you with its
 application id or client id. The partner would typically also create
 a secret or a certificate for their own client applications to use,
 but we aren't concerned with those details. They could use the Azure
 Portal or CLI/PowerShell to create a multi-tenant application registation.
 [A sample CLI script][CreateMultiTenantAppReg] to create such a
 multi-tenant application registration  is provided in this repository.
 2. On your **own** Azure AD tenant and subscription, create a Service
 Principal with the application id from the previous step. The application
 id is in another tenant (`partner-tenant.com`), but given it is a multi-tenant
 one, we are using it the right way. Also create an Event Hubs namespace and
 Event Hub. Assign the service principal permissions to send data to the
 Event Hubs namespace using the built-in role "`Azure Event Hubs Data Sender`".
 [A sample CLI script][CreateSpAndEH] to create a service princial and
 Event Hubs namespace, set the RBAC to permit the service principal to send
 messages to the Event Hubs namespace is provided in this repository.
 3. Simulate an application on the partner side by acquiring an Azure AD
 access token and attempting to send a message to the Event Hubs namespace.
 The token acquisition by the partner application can attempt to acquire
 an access token from 2 Azure ADs. Its own Azure AD tenant
 (`partner-tenant.com`) OR, your Azure AD tenant (`my-tenant.com`). Given
 that the Event Hubs namespace RBAC has specifically granted access to the
 service principal from step 2 above, the only access token which will work is
 the one from your own tenant (`my-tenant.com`). A 
 [sample client application][SamplePartnerRestClient] running in the partner
 tenant is simulated using a REST client application and illustrates how
 tokens are acquired and used to call the Event Hub directly.
 4. A successful send where the partner application acquires an access token
 against your own tenant (`my-tenant.com`) should result in a response like:
 ```
 HTTP/1.1 201 Created
 Transfer-Encoding: chunked
 Content-Type: application/xml; charset=utf-8
 Server: Microsoft-HTTPAPI/2.0
 Strict-Transport-Security: max-age=31536000
 Date: Mon, 17 Apr 2023 12:56:44 GMT
 Connection: close
 ```
 5. Any attempt to use an access token acquired from any other tenant
 against the same Event Hubs namespaces should result in a response like:
 ```
 HTTP/1.1 401 SubCode=40100: Unauthorized
 Content-Length: 0
 Server: Microsoft-HTTPAPI/2.0
 Strict-Transport-Security: max-age=31536000
 Date: Mon, 17 Apr 2023 12:59:03 GMT
 Connection: close
 ```


 <!-- local links -->
 [CreateMultiTenantAppReg]: <./partner-tenant/create-multitenant-appreg.sh>
 [CreateSpAndEH]: <./my-tenant/create-svcprincipal-and-eventhubs.sh>
 [SamplePartnerRestClient]: <./partner-tenant/eh-crosstenant-adtoken.rest?raw=1>
 [ImgEventHubs]: <./docs/media/EventHubs-Multitenant.png>
 [ImgAppReg]: <./docs/media/multitenant-appreg-partner-aad.png>
 [ImgAppSecret]: <./docs/media/secret-appreg-partner-aad.png>
 [ImgGenericSvcMultitenant]: <./docs/media/Service-Multitenant.png>
 


<!-- public links -->
[StorageSas]: <https://learn.microsoft.com/en-us/azure/storage/common/storage-sas-overview>
[EventHubsSas]: <https://learn.microsoft.com/en-us/azure/event-hubs/authenticate-shared-access-signature>
[ServiceBusSas]: <https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-sas>
[ManagedIdentity]: <https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview>
[AADGuestUsers]: <https://learn.microsoft.com/en-us/azure/active-directory/external-identities/add-users-administrator>
[CrossTenantNoNo]: <https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/managed-identities-faq#can-i-use-a-managed-identity-to-access-a-resource-in-a-different-directorytenant>
[RBAC]: <https://learn.microsoft.com/en-us/azure/role-based-access-control/overview>
[MultiTenantAppBasics]: <https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-convert-app-to-be-multi-tenant>
[AppObjVersusServicePrincipal]: <https://learn.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals#relationship-between-application-objects-and-service-principals>

