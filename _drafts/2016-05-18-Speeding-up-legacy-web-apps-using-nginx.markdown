---
layout: post
title: Revitalizing web applications using nginx
---

Introduction
============

The nginx web server keeps impressing me whenever I employ for both my
professional and personal projects. It's outstanding performance, simple
configuration, and rich feature set make using it a no-brainer. Most people
might only view a webserver as a piece of software which delivers static
resources (images, stylesheets, HTML and JavaScript files), nginx also excels
in other roles. My post on [nginx-sso]({% post_url
2015-09-23-nginx-sso-Simple-offline-SSO-for-nginx %}), a simple Single-Sign-On
solution for nginx shows some of nginx's advanced features in action.

This post is about the awesome wealth of proxying functionality that nginx
offers and how it can actually improve the performance and prolong the life of
existing web applications without a lot of effort. In our case we'll see that
the old saying about not being able to polish a turd does not hold true when
talking about legacy web applications. 

Outline
=======
* [Introduction](#introduction) - Different types of SSO designs

<a name="introduction" class="anchor"></a>

The premise: A slow web application
===================================

Let's figure out a good candidate for a slow web application we could tackle.
Before we start, we have to understand what *slow* actually means. Depending on
the software at hand there is not a whole lot that nginx (or any other
software) can do, and the only solution to improve the performance of the
application is to actually rewrite the code. HTTP API endpoints come to
mind. If your API takes a second processing results before it can send out a
reply, you should spend time optimizing your application first.

But that's not really what a web application is. A web application is a
complete set of functionality and resources. Rendered HTML, JavaScript files,
stylesheets, images, fonts, and, yes, API endpoints. Think of software like a
Wiki, an issue tracker, a git frontend, a message board, and pretty much any
commercial software that exposes a web interface. It's the kind of software
that you have to use daily, yet do not have the resources or access to modify
it if it's too slow. It might run in a VM, a Docker container or even on a
locked-down appliance.

![A common website](/images/revitalizing_graph.png "hpfriends shares")
<br/><small>"Yeah, that's more than one request!"</small>

The reason this kind of software runs slowly can be manifold. Often the reason
is simply that deployment was not a priority or that the software was in fact
deployed incorrectly, and now you're stuck with the equivalent of a development
web server which has to handle all of the requests, including static resources.
To make matters worse, the box this software lives on is half a world away from
you in terms of latency. A request typically takes tens to hundreds of
milliseconds.

Prerequisites for proxying via nginx
====================================

For the techniques in this post to work, we need to make sure that the
following conditions are met:

- You have a server which can be reached by your users and which can reach the
  original web app.
- Your server is positioned such that is does not introduce a lot of additional
  latency between the user and the original web app. As a bonus, the server is
  positioned a lot closer to the user than the original web app.
- You can get a domain name and a TLS cert for this server. We'll need this for
  HTTP/2.

These things might be easy to ensure if you're talking about the Internet, but
on a strictly controlled corporate network things might look different.

Tackling performance: Tools at our disposal
===========================================

If you follow web developers at major players (like Google) you notice that a
significant portion of their development effort and education is spent on
improving web performance. As far as the transmission layer is concerned, the
HTTP/2 standard has certainly been the biggest step forward. For us, this will
be the easiest win in terms of web performance.
<!-- FIXME: Rewrite -->

This is a list of things we're going to try:

- Deploying HTTP/2 across the board
- Using TLS session caching
- Deploying TLS best practices
- Setting caching headers for static resources
- Using proxy caching
- Leveraging keepalive and proxy-keepalive
- Replacing content during proxying
- Replacing headers during proxying
 - Rewriting client and server headers
- Tuning proxy buffering
- Setting custom security headers

Show and tell: faz.net
======================
