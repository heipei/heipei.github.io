---
layout: post
title: nginx-sso - Simple offline SSO for nginx
---

**tl;dr**: [nginx-sso](https://github.com/heipei/nginx-sso) is a lightweight,
offline SSO-system which works with cookies and ECDSA. It can easily be used in
together with vanilla nginx and any backend application. The reference
implementation is written in golang and has some cool additional features such
as authorization.

This posts describes the technical background of the system, especially the
motivation for using such a system as opposed to other established SSO
solutions. If you want a technical description of the protocol and the
authentication flow, consult the
[TECHNICAL.md](https://github.com/heipei/nginx-sso/blob/master/TECHNICAL.md) in
the GitHub repository.

Outline
=======
* [Introduction](#introduction) - Different types of SSO designs
* [Features and similar software](#features) - What does nginx-sso do (that others don't)
* [Cookie-based SSO solutions](#cookie-sso) - A look at cookie-based SSO
* [Authentication](#auth_request) - The nginx module that makes this work
* [Authorization](#authorization) - The authorization / ACL functionality of nginx-sso
* [Protecting applications with nginx-sso](#application) - Using this with your app and other software
* [Future Work](#future)
* [References](#references) - Similar projects 

<a name="introduction" class="anchor"></a>

Introduction: Simple web-based SSO
==================================

When I was studying at [RWTH Aachen University](https://www.rwth-aachen.de/), I
had a student-job at the university NOC ([Network Operation
Center](https://www.itc.rwth-aachen.de/)). What might sound like a boring
sys-admin thing was really much more interesting as I got to develop
applications and systems to work for the roughly 50.000 people at the
university.  At some point we were told to make all of our applications work
with the newly introduced SSO-system called
[Shibboleth](https://shibboleth.net/about/basic.html) which we used in
conjunction with
[Grouper](http://www.internet2.edu/products-services/trust-identity-middleware/grouper/).
I'm not going to talk about Shibboleth today as it is a huge system with a
different focus, but one thing that struck me was how easy it was to integrate
applications with Shibboleth, once it was set up.

`Remote-User` and `Remote-Groups`
-----------------------------
Our Shibboleth setup worked by installing an Apache-module for each service
which would perform all of the SSO magic for the backend application. All the
backend application had to do was to consume the HTTP / environment variables
`Remote-User` and `Remote-Groups` and do something with them.

All of the sudden, the headaches of user authentication and management were
gone. No longer did your application have to implement user and credential
storage and authentication, and for authorization if often sufficed to hardcode
a specific Grouper-group into the application. Even better, a lot of available
web applications already had some support for working with `Remote-User`. 

SSO, IdPs, OpenID and OAuth
---------------------------
My time at the NOC ended in 2010. Fast-forward to 2015 and look at the
authentication landscape for modern web applications. Unless you are running
inside some corporate context, chances are you have flirted with using existing
Identity Providers (IdPs) for your project. You can choose between Google,
Facebook, LinkedIn, GitHub and more sites, neatly covering your user-base.
Outsourcing authentication to these guys is a better idea than (mis)handling
user credentials yourself! 

While these options are definitely the way to go for most applications, there
are scenarios where they fall short:

- You might not trust these providers.
- Your applications might live "offline", e.g. in a corporate network.
- You might want to protect static resources.
- You might be put off by the complexity of systems like OpenID Connect.

Another reality nowadays is that your app is quite likely to run behind another
HTTP process. Many people (myself included) today use nginx for terminating
TLS, load-balancing requests, etc. That's why I decided to come up with my own
lightweight SSO which works with nginx and arbitrary applications.

<a name="features" class="anchor"></a>

Features and similar software
=============================

When designing nginx-sso, I came up with a list of necessary and nice-to-have features:

- Work offline: Neither the user nor the service has to talk to the Internet.
- Work disconnected: The service does not have to talk to the Identity Provider.
- Secure: Compromising a service must not impact any other service.
- Provide authentication for backend applications.
- Provide authorization for accessing URIs and dumb backend applications / sites.
- Be simple to understand and setup.
- Work with nginx but not require manually patching / building nginx or maintaining out-of-tree modules.

The [Apache `mod_auth_tkt`](http://www.openfusion.com.au/labs/mod_auth_tkt/)
comes pretty close in terms of functionality. The big difference is that it
works as a native module only on Apache and uses shared secrets.
[Pubcookie](http://pubcookie.org/) is another similar project. It also uses
shared keys and is available as an Apache module. Plus its more complicated.

The project that is closest to nginx-sso is probably
[mod_auth_pubtkt](https://neon1.net/mod_auth_pubtkt/), which uses RSA/DSA. It
includes a lot of similar features, but sadly is also limited to Apache. On the
other hand, it is still actively developed, so if all you need is Apache, it
might be your best choice.

<a name="cookie-sso" class="anchor"></a>

Cookie-based SSO solutions
==========================

When thinking about disconnected / offline SSO it is obvious that the user will
provide his own credentials to the application server which has to decide
whether it is legit. That means verifying the integrity and authenticity of the
users claim, both of which are usually accomplished by using either *MACs* or
*signatures*.

For me, MACs were not an option since an attacker would be able to issue his
own tickets by compromising a single application server. That leaves public-key
signatures, based on DSA or ECC. ECC signatures are the better choice since
they are more efficient and take up less space in a cookie.

nginx-sso uses a plain cookie with an additional ECSDA signature. The signature
is made over the payload of the cookie (username, groups) as well as the expiry
timestamp and the IP of the user.

<a name="auth_request" class="anchor"></a>

Authentication
==============

Authentication using vanilla nginx is possible mostly thanks to an awesome
nginx-plugin called
[auth_request](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html).
From the website:

> The ngx_http_auth_request_module module (1.5.4+) implements client
> authorization based on the result of a subrequest. If the subrequest returns
> a 2xx response code, the access is allowed. If it returns 401 or 403, the
> access is denied with the corresponding error code. Any other response code
> returned by the subrequest is considered an error.
> <br/><small><b>nginx auth_request documentation</b></small>

With this module, every access to configured resources on your nginx server
will trigger an HTTP request to an authentication backend. This request will
contain the headers of the original request which your authentication backend
uses to grant or deny access. The auth_request module is not compiled by
default or in every distribution, but it is part of the mainline nginx codebase
and major distributions have packages compiled with this module.

Here we can see the nginx configuration snippet which protects the resource
`/secret` with a subrequest to the internal resource `/auth` which proxies to
the **ssoauth** server running on localhost.

{% highlight nginx %}
  location = /auth {
    internal;
    proxy_pass http://127.0.0.1:8082;
    proxy_pass_request_body     off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URI $request_uri;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
  }

  location /secret {
    auth_request /auth;
  }
{% endhighlight %}

<a name="variables-backend" class="anchor"></a>

Passing variables to the application
------------------------------------

While I was able to do authentication and authorization in the auth backend, it
still did not help my backend application in identifying the user. Fortunately,
I discovered how to pass variables that are returned by the auth endpoint to the
backend applications, see the example
[nginx.conf](https://github.com/heipei/nginx-sso/blob/master/etc/nginx.conf).
Now the backend service can simply assume the presense and correctness of these
HTTP headers and does not have to deal with the **sso** cookie at all.

{% highlight nginx %}
location /secret {
  auth_request /auth;

  auth_request_set $user $upstream_http_remote_user;
  proxy_set_header Remote-User $user;
  auth_request_set $groups $upstream_http_remote_groups;
  proxy_set_header Remote-Groups $groups;
  auth_request_set $expiry $upstream_http_remote_expiry;
  proxy_set_header Remote-Expiry $expiry;

  [...]
  proxy_information_for_backend_application;
  [...]
}
{% endhighlight %}

<a name="authorization" class="anchor"></a>

Authorization
=============

As a nice side-effect, since we're already making a subrequest for each HTTP
request, we can also use the auth endpoint to do authorization. To do that,
I've implemented a very rudimentary ACL in ssoauth. It has a list of vhosts and
prefixes and for each of those contains a list of allowed users and groups.
This way, even static resources can easily be protected.

{% highlight json %}
"acl": {
  "auth.domain.dev:8080": {
    "Users": ["jg123456"],
    "Groups": ["x:"],
    "UrlPrefixes": {
      "/secret/": {
        "Users": ["ba514378", "jb759123"],
        "Groups": ["y:engineering:cloud"]
      }
    }
  }
}
{% endhighlight %}

<a name="application" class="anchor"></a>

Protecting applications with nginx-sso
======================================

If you are writing a custom application and want to use this (or a similar)
system, it really could not be easier. You can simply use the `Remote-User` and
`Remote-Groups` headers to do authorization, for example by saying *Everyone in
group xyz is an admin*. Alternatively, you can have your own user-database and
only use the `Remote-User` header to create and later look up the correct user.
This way you can have additional attributes (and permissions) for each user.

If you are using stock software you might be able to use this scheme as well. A
lot of software comes with support for logging in via `Remote-User`, even if
the software then implements its own user-database on top of this. For
closed-source software you can sometimes find plugins which enable this
functionality.

<a name="future" class="anchor"></a>

Future work
===========

Development of nginx-sso is at the very beginning, both in terms of code
quality and features. I have a lot of things still written down in my
[TODO](https://github.com/heipei/nginx-sso/blob/master/TODO.md) file. I'd
appreciate any help in making the codebase more readable and examining any
potential weaknesses of the current system. 

<a name="references" class="anchor"></a>

References
==========

- [https://github.com/heipei/nginx-sso/](https://github.com/heipei/nginx-sso/) - The code on GitHub
- [https://neon1.net/mod_auth_pubtkt/](https://neon1.net/mod_auth_pubtkt/) - mod_auth_pubtkt, a project which almost works like nginx-sso
- [http://www.openfusion.com.au/labs/mod_auth_tkt/](http://www.openfusion.com.au/labs/mod_auth_tkt/) - Apache mod_auth_tkt
- [Pubcookie](http://pubcookie.org/) - Pubcookie system
- [https://developers.shopware.com/blog/2015/03/02/sso-with-nginx-authrequest-module/](https://developers.shopware.com/blog/2015/03/02/sso-with-nginx-authrequest-module/) - Describes a basic setup of using auth_request with cookies.
- [https://news.ycombinator.com/item?id=7641148](https://news.ycombinator.com/item?id=7641148) - Hackernews thread discussing auth_request and different approaches to SSO.
- [http://www.vitki.net/book/page/pubcookie-module-nginx](http://www.vanko.me/book/page/pubcookie-module-nginx) - A third-party Pubcookie implementation for nginx, out of date and not maintained.

Social
======

<p>
<a href="https://twitter.com/share" class="twitter-share-button" data-via="heipei">Tweet</a>&nbsp;&nbsp;
<a href="https://twitter.com/heipei" class="twitter-follow-button" data-show-count="false">Follow @heipei</a>
<script>!function(d,s,id){var js,fjs=d.getElementsByTagName(s)[0],p=/^http:/.test(d.location)?'http':'https';if(!d.getElementById(id)){js=d.createElement(s);js.id=id;js.src=p+'://platform.twitter.com/widgets.js';fjs.parentNode.insertBefore(js,fjs);}}(document, 'script', 'twitter-wjs');</script>
</p>


