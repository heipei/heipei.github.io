---
layout: post
title: Persistent AppCache Injections
---

**tl;dr**: Make plain-HTTP MiTM attacks persistent by leveraging the HTML5
AppCache offline functionality. Result: Persistent JavaScript running on the
target browser whenever he visits previously injected websites, will not be
cleared by reload. Can also be used as an intrusion-less persistent Strategic
Web Compromise (SWC) to facilitate reconnaisance and exploitation of selected
targets over time. The actual attack does *not* rely on caching and is
described in [attack](#attack).

* [r/netsec thread](https://www.reddit.com/r/netsec/comments/3h8bbj/html5_persistent_appcache_injections/)
* [Hackernews thread](https://news.ycombinator.com/item?id=10070009)

Outline
=======
* [Introduction](#introduction) - What made me research this attack
* [First thought: Caching](#caching) - How would you do it via Caching
* [Next idea: AppCache](#appcache) - Employing HTML5 AppCache
* [AppCache manifest update behaviour](#update) - A closer look
* [The attack: **Persistent AppCache Injection**](#attack) - Steps to perform the actual attack
* [Examining the persistence](#persistence) - How hard is it to get rid of the AppCache?
* [Attack scenarios](#scenarios) - Where could this attack be employed?
* [Countermeasures](#countermeasures) - What can you do to protect against this attack?
* [References](#references) - URLs for further reading
* [Updates](#updates) - What I found out after finishing this blog-post :(

<a name="introduction" class="anchor"></a>

Introduction
============

Earlier this month a colleague and I gave a talk at [BlackHat USA about the
Great Cannon of
China](https://www.blackhat.com/us-15/briefings.html#bringing-a-cannon-to-a-knife-fight).
If you don't know what the Great Cannon is capable of, I suggest reading the
[excellent technical analysis by the Citizen
Lab](https://citizenlab.org/2015/04/chinas-great-cannon/). The bottom-line is
that the Great Cannon is a nation-level Man-in-the-Middle tool that the Chinese
administration can employ against plain connections going to/from China. With
that tool in hand, they were able to replace ad-related JavaScript hosted on
baidu.com with a malicious piece of JavaScript that would do an XHR request to
GreatFire.org as well as Github.com, thereby creating a browser-based DDoS
attack that international visitors of Baidu participated in. 

While doing my research over the last months, I tried to come up with
worst-case scenarios and payloads that could be employed against plain HTTP
connections this way. Right from the start it had been evident that the Great
Cannon could also be used to target individual users and organizations. The
selectors for this targeting could be plain IP addresses or other user traits
submitted via plain HTTP. HTTP injection is noisy however, especially since it
has to be performed constantly against a user. For the Great Cannon this might
be possible, but for an attacker trying to MiTM your HTTP connection, this is
frequently not the case.

I realized that the scariest way to achieve this goal is by somehow
*persisting* in the target browser after the injections have stopped. This way
you could track users over extended periods of time, either as part of a
botnet, to collect information, or to wait for the day that their browser or
plugins are vulnerable to a remote-code-execution bug for a short period of
time.

<a name="caching" class="anchor"></a>

First thought: Caching
======================

When thinking of persistence and HTTP, browser caching is the first thing that
comes to mind. You could supply injected content along with custom caching
headers which have a long cache duration. This will actually work reasonably
well, but suffers from a couple of drawbacks:

- If you inject single JS files, there is no telling whether the URL for these
  changes (e.g. asset management URLs).
- If you inject some HTML resource, the user might notice that the website on
  his system seems out of date and force a refresh.
- In any case, as soon as the website starts behaving erratically, users are
  likely to manually refresh the websites, thereby clearing the caches and your
  precious payload.

The caching behaviour of different browsers is a complicated topic that I'm not
gonna get into here. Suffice to say, major browsers nowadays offer easy ways of
clearing the cache or hard-reloading a page.

<a name="appcache" class="anchor"></a>

Next idea: AppCache
===================

My next idea was to go with the HTML5 Application Cache, aka the "offline
website" functionality. You might have seen that in action when you used Google
Docs and went offline: The web application is still available and fully
usable.

The way that the AppCache works is by specifying a manifest file in the HTML
header that tells the browser to download all of the files in the manifest and
use them whenever the browser is determined to be offline. You can then make a
website appear to be offline by DoSing either or cookie-bombing the user so the
website appears to be offline. Both approaches make the actual website
unreachable, which we want to avoid for obvious reasons.

Interestingly, the files in the AppCache are used even when the browser is
online. In this case, the only thing the browser does is to check whether the
manifest file changed. If it hasn't it will happily keep using the offline
files.

The obvious approach would be to inject a forged HTML, manifest and
corresponding cache headers. Apparently, the cache headers are also applied to
the manifest file. This is exactly what [Egor
Homakov](http://sakurity.com/blog/2015/08/13/middlekit.html) did in his post on
the Application Cache. But this approach suffers from the same drawbacks that
pure cache-based attacks to: It can easily be circumvented by clearing the
cache or hitting hard-refresh. For Safari, this will not work at all, since it
will always check the manifest even if it had a long cache expiry time.

<a name="update" class="anchor"></a>

AppCache manifest update behaviour
==================================

I started looking at the [HTML5
spec](http://www.w3.org/html/wg/drafts/html/master/browsers.html#offline) and
playing around with the Application cache. When you reload a page, the browser
will try to get the manifest to see if it changed. If the manifest file is gone
(HTTP 404 or 410), then the whole Application Cache will be cleared. This would
defeat our one-time injection.

What caught my eye was this piece section:

> Otherwise, if fetching the manifest fails in some other way (e.g. the server
> returns another 4xx or 5xx response or equivalent, or there is a DNS error,
> or the connection times out, or the user cancels the download, or the parser
> for manifests fails when checking the magic signature), or if the server
> returned a redirect, or if the resource is labeled with a MIME type other
> than text/cache-manifest, then run the cache failure steps.
> <br/><small><b>[W3C HTML5 spec](http://www.w3.org/html/wg/drafts/html/master/browsers.html#downloading-or-updating-an-application-cache)</b></small>

The cache failure steps finish with this step: *"Abort the application cache
download process."* To spell it out: The Application cache will stay intact if
some part of updating it fails this way. The reasoning behind this is that the
user might be behind some sort of captive portal (hence the 302), which
effectively means "offline". The same logic is true for return codes like
500 ("The server might be down") or 200.

I only noticed the *"Security Concerns"* section in the draft spec after I had
already come up with my attack.  It addresses a very similar attack, but still
does not quite apply to what we have in mind.

> [...] an injection attack can be elevated into persistent site-wide page
> replacement. [...] Targetted denial-of-service attacks or cookie bombing
> attacks can be used to ensure that the site appears offline. [...] If a site
> has been attacked in this way, simply removing the offending manifest might
> eventually clear the problem, since the next time the manifest is updated, a
> 404 error will be seen, and the user agent will clear the cache. [...]
> Unfortunately, if a cookie bombing attack has also been used, merely removing
> the manifest is insufficient; in addition, the server has to be configured to
> return a 404 or 410 response instead of the 413 "Request Entity Too Large"
> response.
> <br/><small><b>[W3C HTML5 spec](http://www.w3.org/html/wg/drafts/html/master/browsers.html#downloading-or-updating-an-application-cache)</b></small>

<a name="attack" class="anchor"></a>

Putting everything together: Persistent AppCache Injection
=======================================

Now for the actual attack. Let's take a step back and see what we've got:

* We can't upload our own manifest to the server.
* We can't inject a response for every request to the manifest.
* We can't / won't DDoS or cookie-bomb the server.
* The manifest has to live in the same origin as the website.
* The AppCache **will** be deleted if the request for the manifest returns 404 or 410.
* The AppCache **will not** be deleted if the manifest returns some other error code or redirect.
* The AppCache **will not** be deleted if the manifest returns 200 but with the wrong MIME type.
* **No** current browser will prompt or show any indication when creating an AppCache.

In order to achieve our intended persistence, we need to inject the manifest on
a path that will generate a non-404/410 response from the **legitimate**
web-server! The path can be any sub-path, just make sure to deliver your fake
manifest file with MIME-type `text/cache-manifest`.

* Inject resource you want to persist (e.g. /index.html or just /).
* In injected resource, point to your own to-be-injected manifest via `<html manifest="/foo/bar/">`.
* Make sure that the URL for fake manifest always returns non-404/410 from the legitimate website.
* Additionally, place JavaScript payload in the injected resource (stealthier).
* The manifest should include the resource, itself, and whatever else you need.
* Do the injection once.

The injected HTML at /:
{% highlight html %}
<html manifest="/foo/bar/">
    <head><title>Malicious Website</title></head>
    [...]

{% endhighlight %}

The injected manifest file at `/foo/bar/`:
{% highlight bash %}
CACHE MANIFEST

CACHE:
/
/foo/bar/
{% endhighlight %}

Picking a non-404/410 URL might sound complicated, but it's actually fairly
simple: Pick any 302 or even 200 URL (as long as it does not reply with
MIME-type `text/cache-manifest`.

<a name="persistence" class="anchor"></a>

Examining the persistence
=========================

This is where things get tricky. The question we want to answer is how
persistent our injection really is. Remember that the AppCache functionality is
supposed to work offline, so clearing the AppCache when the user hits
*"Reload"* would defeat its purpose. Let's have a look at each major browser:

Google Chrome 44 (Stable) (Linux & Mac OS X)
--------------------------------------------

Google Chrome will **not** clear the AppCache or reload the original HTML when
doing a refresh or hard-refresh (Ctrl-Shift-R). It **will** reload the original
file when opening the Inspector and selecting `[x] Disable Cache`. Also, you
can examine and clear AppCaches in chrome via the internal URL
`chrome://appcache-internals/`.

Mozilla Firefox 38.1.1 (ESR) (Linux & Mac OS X)
-----------------------------------------------

Firefox will **not** clear the AppCache when doing a refresh or hard-refresh.
The only way to clear the AppCache is to go to *Preferences* -> *Advanced*
-> *Network* and clear the AppCache manually.

Safari 8.0.7 (Mac OS X) 
-----------------------

Safari will **not** clear the AppCache on refresh or hard-refresh. On top of
that, Safari will also **not** clear the AppCache even if you do *Develop* ->
*Empty Caches* and *Develop* -> *Disable Caches*.

Safari does not expose the AppCaches in a very visible fashion. The only way
I've found to clear an AppCache is by going to *Preferences* -> *Privacy* ->
*Remove All Website Data* (or search for websites).

Opera 31.0 (Mac OS X)
---------------------

Opera will **not** clear the AppCache on refresh or hard-refresh (Shift+Refresh).
Opera will clear the AppCache when hitting *Clear Browsing Data*.

Internet Explorer 11 (Windows 7)
--------------------------------

Internet Explorer will **not** clear the AppCache on refresh or hard-refresh
(Shift-Click). To clear it, you'll have to go to *Internet Options* ->
*Settings* -> *Caches and databases*.

Comparison to Homakov
---------------------
Comparing the method to the Cache-Only attack of Homakov:

Our method:

{: .table .table-borders}
| Method | Chrome | Firefox | Safari | Opera | IE |
| -------| ------ | ------- | ------ | ----- | -- |
| Reload / Browse | Persist | Persist | Persist | Persist | Persist |
| Hard-Reload | Persist | Persist | Persist | Persist | Persist |
| Cache disable | Clear | NA | Persist | NA | Clear |
| Preferences | Clear | Clear | Clear | Clear | Clear |

Homakov:

{: .table .table-borders}
| Method | Chrome | Firefox | Safari | Opera | IE |
| -------| ------ | ------- | ------ | ----- | -- |
| Reload / Browse | Persist | Persist | Persist once | Persist | Persist |
| Hard-Reload | Persist | Persist | Clear | Persist | Persist |
| Cache disable | Clear | NA | Clear | NA | Clear |
| Preferences | Clear | Clear | Clear | Clear | Clear |

As I said, browser caching is a complex topic. Suffice to say, employing only
caching is not sufficient since the browser might clear the cache without a lot
of user interaction. For example, Safari will clear the cache if you hit the
regular "Reload" twice in a row.

<!-- TODO: Table to compare against Homakov's attack -->

<a name="scenarios" class="anchor"></a>

Attack scenarios
================

There are a number of different scenarios where this attack can be used, ranging from stealthy to obvious.

The Great Cannon (or any large in-path system) could be leveraged to do these
kind of injections. This would have to be very targeted, as any large-scale
injection will immediately be noticed. Additionally, if someone already
controls a system such as the Great Cannon, he would not really have to do
these kind of injections to stay "persistent".

Another scenario is much more dangerous: **Local injections**. If you're going to a
conference or browsing over a public hotel Wi-Fi, someone could MiTM you and
thereby persist in your browser whenever you visit your favorite website.
Personally, I browse a number of plain-only news websites which would be ripe
targets as I go there daily and usually stay for a while to catch up on news.

An even more devious kind of injection would work against **internal websites**
that the target might visit. This could be your average Intranet page which IT
never protected with HTTPS since *"it's only reachable on the corporate
network"* anyway. Usually, the target would not visit these websites in a
remote location, but he might have had an open tab or simply didn't notice that
the VPN connection had died again. In any case, you can now inject his
**internal** website and grab whatever data you want the next time he goes
online in his corporate network/VPN environment. Scary? It should be!

Both of these attacks could also be carried out without actually *injecting*
the HTTP response. You could simply send a forged DNS reply to redirect the
target to your AppCache-injection site once.

Lastly, as I mentioned, this kind of persistence would be ideal for actors
without nation-state capabilities to pull of targeted exploitation. Without
access to a treasure trove of 0days, you'd have to be lucky to catch your
target in the narrow time-frame that he is exploitable. With a persistent
injection, you could simply wait until there is yet another Flash/Java RCE 0day
and exploit the user in this very instant.

Not really an injection, but this attack could just as well be mounted by an
attacker who compromises the legitimate webserver and wants to persist even
after his attack payload is cleaned from the server. In this case, the benign
website could at least detect the injection and make sure it returns 404 for
the fake manifest URL.

<a name="countermeasures" class="anchor"></a>

Countermeasures
===============

To prevent this attack from taking place in the first place, one should employ
**HTTPS along with HSTS whenever possible**. HTTPS is **not enough** if users
go to the plain HTTP URL: Deploy HSTS! There is a [free CA launching this
year](https://letsencrypt.org/), and the steps to actually get a proper HTTPS
setup working have never been easier. If you're in a corporate environment, you
could set up your own CA and install its cert with your users. Make sure you
understand the security-implications of this though! Custom CAs will not
trigger key-pinning violations!

A mitigation if your website was attacked via an inject would be to change the
requested paths for the faux manifest file to return 404 instead of some other
return code.

Other things that could be done by Browser vendors would be to make the
AppCache more visible to the user, via a dedicated icon in the address-bar that
shows that the offline version of a page is in effect. Another feature or
extension could be created which only allows AppCache to be set by HTTPS sites,
which would get rid of the injection attack.

<a name="references" class="anchor"></a>

References
==========

* [Attack & Defense Labs: HTML5 AppCache attack](http://blog.andlabs.org/2010/06/chrome-and-safari-users-open-to-stealth.html)
* [HTML5 attacks by Krzysztof Kotowicz](https://www.hackinparis.com/slides/hip2k12/Krzysztof-html5-somethingwickedthiswaycomes.pdf)
* [Wikipedia: Bypass your cache](https://en.wikipedia.org/wiki/Wikipedia:Bypass_your_cache#Bypassing_cache)
* [Egor Homakov: Using AppCache and ServiceWorker for Evil](http://sakurity.com/blog/2015/08/13/middlekit.html)
* [W3C HTML5 spec on Offline Web Applications](http://www.w3.org/TR/2011/WD-html5-20110525/offline.html)
* [Appcache Facts](http://appcache.offline.technology/)

<a name="updates" class="anchor"></a>

Updates
=======

I had previously searched for existing documentation of this attack vector but
could not find any mention of it. It was only *after* I had finished my
research and this blog post that I came upon the [blog-post by Attack&Defense
Labs](http://blog.andlabs.org/2010/06/chrome-and-safari-users-open-to-stealth.html)
which describes the exact same attack :( It was then rehashed in [this
presentation by Krzysztof
Kotowicz](https://www.hackinparis.com/slides/hip2k12/Krzysztof-html5-somethingwickedthiswaycomes.pdf).
I guess I only searched for "injection" rather than "poisoning". Nevertheless,
I still published this post as it should serve as a useful refresher and
reminder and also examines different browsers and attack vectors.

As I'm not a cutting-edge kind of WebDev, I was not aware that AppCache will
actually be replaced by
[ServiceWorkers](http://www.w3.org/TR/service-workers/). In the future, browser
vendors might drop AppCache support, at which point it will be removed from the
spec as well. Older browser will still support it though, and there is no
timeline yet for when it will be removed.

Social
======

<p>
<a href="https://twitter.com/share" class="twitter-share-button" data-via="heipei">Tweet</a>&nbsp;&nbsp;
<a href="https://twitter.com/heipei" class="twitter-follow-button" data-show-count="false">Follow @heipei</a>
<script>!function(d,s,id){var js,fjs=d.getElementsByTagName(s)[0],p=/^http:/.test(d.location)?'http':'https';if(!d.getElementById(id)){js=d.createElement(s);js.id=id;js.src=p+'://platform.twitter.com/widgets.js';fjs.parentNode.insertBefore(js,fjs);}}(document, 'script', 'twitter-wjs');</script>
</p>


