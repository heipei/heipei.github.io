---
layout: post
title: OpenSSH - Secure Networking Swiss-Army Knife
---

**tl;dr**: Well-known yet underused OpenSSH features and their applications in
building secure systems.

* [r/netsec thread](https://www.reddit.com/r/netsec/comments/34az9p/openssh_secure_networking_swissarmy_knife/)
* [Hackernews thread](https://news.ycombinator.com/item?id=9460608)

Introduction
============

My [last post on this
blog](/2015/02/26/SSH-Agent-Forwarding-considered-harmful/) was about the
dangers of using SSH Agent Forwarding. In that post I recommended using OpenSSH
`ProxyCommand` as not only a workaround but actually a superior way of hopping
between hosts. This feature is clearly documented and intended to be used as
such, still a lot of the discussions which ensued on Reddit and Netsec showed me
that there are quite a number of users who were previously unaware of these
features. That's what prompted me to do a follow-up on some additional
"tricks", even if it's just the application of something clearly documented in
the manpages. But then, not everybody reads the manpages.

This post will cover some of these features and also provide some references
for further reading. I'll start by introducing the basic features and then
presenting some ways to use them. The biggest takeaway is this:

> OpenSSH is a lot more than a tool to securely to connect to your VPS. Think
> of it as a simple, well-understood building-block for constructing secure
> distributed systems, for both automated and interactive applications. With
> the right workflow, employing OpenSSH will come to you very naturally and
> comfortably.
> <br/><small><b>Me, April 2015</b></small>

Securing OpenSSH
================

We start of by applying reasonable security settings to our OpenSSH workflow.
In the recent months there were enough posts written on this topic, so I'll
just reference them here. It boils down to this:

* Protecting your private key with a passphrase.
* Disabling logins via password.
* Explicitly disallowing all but the most secure Ciphers, MACs and Key Exchange algorithms.
* Monitoring and preventing brute force connections.

The most current and comprehensive post on this topic has been written by
[@stribika](https://twitter.com/stribika) in his blog-post [Secure Secure
Shell](https://stribika.github.io/2015/01/04/secure-secure-shell.html). His
observations are spot-on, including the section on "System hardening": <i>Keep
a clean system</i>.

What I like to do on top of this is to employ some way of monitoring the SSH
logs and rate-limiting connection attempts in a very crude way. Monitoring SSH
connection attempts can be done by logging TCP connections to your SSH ports
and then ingesting these logs into something like Logstash and Kibana. To
rate-limit connection attempts I use a very simple iptables ruleset because I
don't trust systems like fail2ban enough.

* Move your SSH to a high port instead of running it on tcp/22. This will
  eliminate practically any noise in the TCP logs: `Port 12345` in `sshd_config`
* Setup rate-limiting to your SSH listening port just in case:

{% highlight bash %}
iptables -A INPUT -p tcp --dport 12345 -m conntrack --ctstate NEW -m recent --set
iptables -A INPUT -p tcp --dport 12345 -m conntrack --ctstate NEW -m recent \
	--update --seconds 120 --hitcount 3 -j DROP
iptables -A INPUT -p tcp --dport 12345 -j ACCEPT
{% endhighlight %}

* On a multi-user system it might be reasonable to disallow some features
  globally, such as agent forwarding, port forwarding and dynamic port
  forwarding.
* If you're adventurous you can also employ [port-knocking using nothing but
iptables](https://www.digitalocean.com/community/tutorials/how-to-configure-port-knocking-using-only-iptables-on-an-ubuntu-vps).

~/.ssh/config
=============
Next we turn our attention to your `~/.ssh/config` file. This file can be used
to configure per-host parameters, most commonly a combination of a custom port
and username.

You should consider `~/.ssh/config` your authoritative and only sources about
your hosts. Whenever you get access to a new host just add it to this file and
don't worry about remembering it. The `Host` line can be used to create aliases
which are easy to remember (e.g. `ams-vps` instead of a raw IP).

Let's examine a contrived example to show the options I find myself most frequently using:
{% highlight apache linenos %}
ServerAliveInterval 10
TCPKeepAlive no

Host ams-vps
	Hostname 123.123.123.123
	Port 12345
	User root
	IdentityFile ~/.ssh/vps_key
	IdentitiesOnly yes
	LocalForward 8080 localhost:80
	DynamicForward 9090
{% endhighlight %}

Let's go through these lines one by one, ignoring the "Alive" lines.

- The `Host` alias is `ams-vps` so I can remember it easily.
- The `Hostname` is the actual IP or hostname of the host.
- It uses a non-standard `Port`.
- I have to login with a different user than on my local machine.
- I have a separate keypair for this host in `vps_key` and I only want to use that one.
- I want to be able to access `tcp/80` on the remote host via `localhost:8080`.
  - This is great if you want to access some piece of remote software which you
   would not want to expose on the Internet. Like a plain HTTP server, or a
   VNC-server if you're running virtual machines on the remote host.
- I want a SOCKS proxy server listening locally on `tcp/9090` terminated with the remote host.
  - Using a SOCKS proxy I can easily tunnel a lot of traffic through this
    machine, for example to circumvent geo-IP restrictions. I could use my
    browser to use this proxy and then browse via the remote host. With Chrome,
    this works best by using a separate profile, so you can keep your regular
    profile running without the proxy.

{% highlight nginx %}
   google-chrome-stable
   --user-data-dir=$HOME/.config/google-chrome-socks
   --proxy-server=socks://localhost:9090
{% endhighlight %}

My `~/.ssh/config` is currently ~250 lines long, just to give you an idea. The
newest versions of OpenSSH even allow include statements in this file.

ControlMaster
=============
OpenSSH `ControlMaster` is one of the options that I use globally in my `~/.ssh/config`. 

{% highlight apache %}
ControlMaster auto		# Auto == Create and use as needed
ControlPath /tmp/%r@%h:%p	# The sockets are stored here
ControlPersist yes		# Optional
{% endhighlight %}

What `ControlMaster` does is create (and subsequently use) a control socket
for each connection to a remote server. SSH supports multiple independent
"channels" which can be multiplexed over a single existing SSH connection. On
the first connection to a host, OpenSSH will create a control socket in `/tmp`.
With each subsequent connection, if a ControlMaster exists for a given
user/host/port, OpenSSH will use it to create a new channel (pty or scp) within
the existing SSH connection without going through the SSH handshake and shared
secret agreement. The socket will be destroyed when the last SSH session
disconnects.

The biggest reason for me to use `ControlMaster` is _performance_. The SSH
handshake does take a while, even more so with increasing latency. While this
might not be an issue for the occasional login, it is really annoying or
downright prohibitive when trying to connect more frequently. The prime example
here is remote scp-completion, something that zsh is capable of doing out of
the box. Unless you're on your local network, scp-completion just plain sucks
without `ControlMaster`. The problem is even amplified when considering
scenarios with more than one hop (`ProxyCommand`). In this case, each full SSH
session establishment can take several seconds.

The `ControlPersist` keyword is optional. I don't use it because I like to keep
track of the open session, but software like Ansible employs it to have the
control socket linger for a while after the last/initial SSH connection is
closed.

ProxyCommand
============

I'm not going to talk about `ProxyCommand` at length since I mentioned its
benefits in my [last
post](/2015/02/26/SSH-Agent-Forwarding-considered-harmful/). As a quick recap:
`ProxyCommand` allows your system to connect to an otherwise inaccessible system
via one or multiple intermediate "hops". It has undeniable advantages in terms
of usability and security over using something like SSH agent forwarding. The
number of ways you could get pwned when not using `ProxyCommand` is not
something to be dismissed lightly.

Suffice to say, none of the features I mentioned in this post (`LocalForward`,
`DynamicForward`, `ControlMaster`) work if you use agent forwarding or manual
hopping as opposed to using `ProxyCommand`. One more reason to reconsider.

~/.ssh/authorized\_keys
=======================

The `authorized_keys` file specifies which public key is allowed to login to
the current account. You've probably used it when adding your own public key on
a remote server. The basic format of this is very simple: It takes one SSH
public key per line to allow login via that key.

Some people might not know that you can actually add a number of options per
key. The complete description is in `man sshd`, I'll only cover the options I
frequently use.

{% highlight vim %}
command="date",no-agent-forwarding,no-pty,no-port-forwarding,permitopen="192.168.1.1:22" ssh-rsa AAAAB3Nza
{% endhighlight %}

* `command` will execute a fixed command for each login with this public key, ignoring any other commands supplied by the client.
* `no-agent-forwarding` and `no-port-forwarding` will disallow agent/port forwarding.
* `no-pty` will disallow pty allocations, useful for automation.
* `permitopen="host:port"` will only allow port forwards to this host/port. Can be repeated.

Using these options, one can use OpenSSH with a passphrase-less dedicated key
for some unsupervised applications:

* A key which periodically calls the forced command (like a monitoring script).
* A key for permanently port-forwarding a (remote) port of an insecure
  application from A to B.
* A key which can only do backups to a certain location using a
  [forced command like
  rrsync](https://www.guyrutenberg.com/2014/01/14/restricting-ssh-access-to-rsync/).
* A key which can only forward to another internal SSH host (`ProxyCommand`).

For a constant connection you can simply run `ssh` via some process supervisor
like runit.

Conclusion
==========

The intention of this post was to show that OpenSSH is much more than just a
remote-login tool. It can be used for various automated applications. The nice
thing about using SSH for these cases is that it is cross-platform, dead-simple
to setup, test and to actually understand the security and features offered by
such a solution.

Want to forward a single port with some low-bandwidth yet high-value traffic
over the Internet? Why set up a complicated VPN solution when you know how to
use SSH? Want to have automated backups? Use SSH! Even if you only use SSH
interactively, this post might have shown you a few tricks to improve your
workflow.

Having something that a user already understands and which does not introduce a
new attack surface is a huge security win in my opinion. The tendency of some
modern software is to just bind to localhost and omit any form of
authentication or transport security. Here, SSH can be used as a security
layer, even if only during development. The same is true for supposedly secure
protocols which you still don't trust entirely. Used correctly, OpenSSH is a
very robust system that does authentication, authorization and proper transport
security and is part of every conceivable distribution. Also consider that
OpenSSH is one of the pieces of your userland toolkit which is most closely
reviewed and at the same time still being actively developed by the OpenBSD
community.

Going further
=============

Topics not mentioned here include:

* [mosh](https://mosh.mit.edu/) - A roaming-friendly secure shell built upon SSH
* [autossh](https://www.harding.motd.ca/autossh/) - Automatically restarts SSH session
* [dropbear](https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#Remote_unlocking_of_the_root_.28or_other.29_partition) - To remotely unlock LUKS-protected root drives
* [sshfs](https://wiki.archlinux.org/index.php/Sshfs) - FUSE-based remote mounting of paths

References
==========

* [Arch Linux Wiki on OpenSSH](https://wiki.archlinux.org/index.php/Secure_Shell) - Not surprisingly a very exhaustive reference.
* [ssh tricks - the usual and beyond](https://www.jedi.be/blog/2010/08/27/ssh-tricks-the-usual-and-beyond/) - Good post covering most of the same topics.
* [Secure Secure Shell](https://stribika.github.io/2015/01/04/secure-secure-shell.html) - Timely OpenSSH crypto hardening post.
* [OpenSSH hardening tips](http://docs.hardentheworld.org/Applications/OpenSSH/)
* [ProxyCommand multi-hop magic](http://sshmenu.sourceforge.net/articles/transparent-mulithop.html)
* [logstash ingestion of iptables logs](https://home.regit.org/2014/01/a-bit-of-logstash-cooking/)
