---
layout: post
title: Jekyll and responsive Flickr photos
---

Introduction
============

My personal blog over at [heipei.net](https://heipei.net) is a little different to this one. Rather than text- and
code-heavy content, it is mostly photos with some text in between. I've already spent countless hours optimizing every
performance aspect of the site, sometimes including brand-new directives such as preconnect hints. But at some point
there is no way around the fact that the blog contains a lot of high-fidelity images from Flickr, a site that is known
to not compress it's photos aggresively, which is a good thing for photographers.

So the only way to improve the perceived performance is to load photos only when they are needed, i.e. when they're
about to become visible. This is known as *lazy-loading* and can be accomplished quite easily using a variety of
JavaScript libraries. I combined lazy-loading with a simple mechanism for responsivesness to make it work better for my
use case. This will certainly not fit all applications, but should give you an idea just how easy it is do implement
something like this yourself.

Getting flickr photo URLs
=========================

Flickr used to have a more generic *Share* dialog. Unfortunately, nowadays they only offer an intrusive JavaScript-based
snippet for embedding photos in your website. It works well enough, but neither do I need it nor do I want additional
JavaScript on my site. The way I go about this is to copy the *Embed* URL and transform it in my paste-buffer:

{% highlight html %}
<a data-flickr-embed="true"  href="https://www.flickr.com/photos/heipei/26979354391/in/photostream" title="Wanderung
Grenzroute 2"><img src="https://c8.staticflickr.com/8/7245/26979354391_54884d1976_b.jpg" width="1024" height="683"
alt="Wanderung Grenzroute 2"></a><script async src="//embedr.flickr.com/assets/client-code.js" charset="utf-8"></script>
{% endhighlight %}

Transformed via:
{% highlight bash %}
pbpaste|sed -e "s/data-.*  href/href/" -e "s/\/in\/dateposted-public//" -e "s/width.*alt/alt/" -e
"s/<script.*script>//"|pbcopy
{% endhighlight %}

which gives me: 

{% highlight html %}
<a href="https://www.flickr.com/photos/heipei/26979354391/in/photostream" title="Wanderung Grenzroute 2"><img
src="https://c8.staticflickr.com/8/7245/26979354391_54884d1976_b.jpg" alt="Wanderung Grenzroute 2"></a>
{% endhighlight %}

This is the format I use in my Jekyll blog-posts. I get rid of `width` and `height` as well since I might always change
the dimensions of this blog in the future.

Lazy loading
============

For lazy-loading, I used the [echo.js library](https://github.com/toddmotto/echo), though I suppose that any similar
library would do. The way that echo.js works is by not setting the `src` attribute of the image but rather setting the
URL of the image in the `data-echo` attribute. Then, at runtime, the echo.js library can set the `src` attribute just in
time when the viewer is about to scroll to the image.

{% highlight html %}
<img src="loading.gif" data-echo="https://flickr.com/photo.jpg">
{% endhighlight %}

I've used a variety of these libraries over the lifetime of my blog, so whenever I switched to a new one I would have to
go back and edit the image tags of all old post to accomodate the new way the library would do lazy loading. Quite
painful. Since I'm using Jekyll now I've simply included a preprocessing step for image tags. In `_layouts/post.html`
I'm using

{% highlight ruby %}
{% raw %}
{{ content | replace_regex: 'img src=', 'img src="/images/ajax.gif" data-echo=' }}
{% endraw %}
{% endhighlight %}

Which will transform regular image tags like

{% highlight html %}
<img src="https://c8.staticflickr.com/8/7245/26979354391_54884d1976_b.jpg" alt="Wanderung Grenzroute 2">
{% endhighlight %}

into this HTML for the output:
{% highlight html %}
<img src="/images/ajax.gif" data-echo="https://c8.staticflickr.com/8/7245/26979354391_54884d1976_b.jpg" alt="Wanderung Grenzroute 2" />
{% endhighlight %}

The beauty of using the Jekyll processing step is that I can turn echo.js of at
any moment if I no longer want to use it.

Responsive flickr images
========================

Lazy loading already works wonders for page-load speed on any device. The other big issue that I faced was the enormous
size of flickr photos. For landscape-photos, I include the *large* size, which is 1024px wide. For my latest post, just
[the first photo](https://c8.staticflickr.com/8/7245/26979354391_54884d1976_b.jpg) is a whopping 362kB of incompressible
JPG data. The next smaller size, called *medium* at 800px wide, is 250kB in size, already a big improvement. For small
devices (say 480px wide), I can get away with the *medium* size at 500px wide at about 100kB, a three-fold improvement. 

Flickr offers photos in a variety of pre-defined sizes, [indicated by the filename
suffix](https://www.flickr.com/services/api/misc.urls.html). This makes it straightforward to replace images with a
simple substitute. I thought about it a little bit, and came up with this simple workflow:

- Images are included in the page in their biggest size, using the `data-echo` attribute
- If an image has width/height set, those settings will be removed
- I will only downsize images that have not been loaded yet
- I will upsize images that have already been loaded, if the size of the viewport changes
- I'm replacing *large* (1024px) images with *medium* (500px) images (360kB to 100kB for our example)
- I'm replacing *medium* (800px) images with *small* (320px) images (250kB to 37kB for our example)

Comparing a desktop load and a simulated Nexus 5x load of my most recent blog post:

![Desktop load](/images/jekyll-flickr-native.png "Desktop load")
<br/><small>Desktop load</small>

![Mobile load](/images/jekyll-flickr-mobile.png "Mobile load")
<br/><small>Mobile load (Nexus 5x)</small>

This is the simple Coffeescript-code to achieve just that
{% highlight coffee %}
document.addEventListener( "DOMContentLoaded", () ->

  resize_flickr_images = (size="small") ->
    imgs = document.querySelectorAll("img")
    for img in imgs
      for attrib in ["data-echo", "src"]
        original_url = url = img.getAttribute(attrib)
        continue unless url?

        # Remove width/height for all flickr images
        if url.match("https://.*\.static\.?flickr.com/.*")
          img.removeAttribute("width")
          img.removeAttribute("height")

        # Only downsize images if they haven't been loaded yet (data-echo)
        if size is "small" and attrib is "data-echo"
          if url.match("https://.*\.static\.?flickr.com/.*_b.jpg")
            url = url.replace("_b.jpg", ".jpg") 
          else if url.match("https://.*\.static\.?flickr.com/.*_c.jpg")
            url = url.replace("_c.jpg", "_n.jpg") 
        
        # Always upsize flickr images
        if size is "large"
          if url.match("https://.*\.static\.?flickr.com/.*_n.jpg")
            url = url.replace("_n.jpg", "_c.jpg") 
          else if url.match("https://.*\.static\.?flickr.com/.*_m.jpg")
            url = url.replace("_m.jpg", "_n.jpg") 
          else if url.match("https://.*\.static\.?flickr.com/.*/[a-f0-9]{3,}_[a-f0-9]{3,}.jpg")
            url = url.replace(".jpg", "_b.jpg") 

        if original_url isnt url
          img.setAttribute(attrib, url)

  WidthChange = (mq) ->
    if mq.matches
      resize_flickr_images("small")
    else
      resize_flickr_images("large")
    return

  if matchMedia
    mq = window.matchMedia('(max-width: 480px)')
    mq.addListener WidthChange
    WidthChange mq

  # Init echo.js lazy loading
  echo.init
      offset: 400,
      throttle: 150,
      unload: false

)
{% endhighlight %}

TODO
====

This is still a very crude and not quite generic way to resize flickr photos. I imagine this could be done in a more
generic fashion, e.g. as a small JavaScript library that can be included into pages to make any included flickr photos
more responsive. But, as you can tell from the code above, the time spent searching for a library which does exactly
what you need and does not interfere with the rest of your page usually takes longer than simply writing a few lines of
JavaScript or CoffeeScript yourself.

If you have ideas on how to improve upon these techniques, let me know via the
comments! I'll upload the Jekyll source of my main blog to GitHub soon, once
I've cleaned up the code base a little bit.
