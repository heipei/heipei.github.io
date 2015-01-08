---
layout: post
title: UDF for cross-OS file-transfer using removable media
---

Introduction
============

Ever since you started using more than one OS you knew the inherent problems of exchanging data between different OSs.
Unless you transfer everything via network, you will have to make a choice regarding the filesystem on a removable
drive.

For this post we consider the common scenario of wanting to move files between Linux, Mac OS and Windows. If you
consider only a subset of these you might get away with other filesystems as well. Each filesystem you choose will have
a number of limitations. Some might be read-only in one or two of the destination OSs, others might have limits on the
filesize (4GB anyone?) and yet others might require you to install closed-sourced commercial software to use them.

Up until recently, I would use FAT32 to exchange files (or backups) between devices. This worked reasonably well, but in
2014 you can expect to have a number of files which exceed FAT32s 4GB limit on filesize. Only think about Virtual
Machine images!

Recently, I stumbled on a surprisingly simple solution for my problem: UDF! Everybody knows and supports UDF (Universal
Disk Format) because it's the filesystem used on DVDs etc. Reading about UDF, it's also the filesystem for DVD-RAM (a
relic disk format which could be used to create incremental backups by burning them to a DVD disk). I never thought
about it, but UDF can also be used as a filesystem for read-write media, and current operating systems support it just
fine. To top it of, UDF is both case-sensitive and case-preserving and has POSIX file permissions, not something to take
for granted even with modern filesystems. A tabular feature comparison between UDF, NTFS, FAT32 and exFAT can be found in
the [Windows Dev Center](http://msdn.microsoft.com/en-us/library/windows/desktop/ee681827).

Creating a UDF drive
====================

Now, this is the tricky part, and the one where your mileage might vary wildly. Please contact me with any improvements
on these steps. For this I'm assuming that I have a Linux host to create the UDF filesystem and a Mac OS X host to use
it with.

On Linux, install mkudffs (package udftools). Insert the drive you want to format using UDF (sdb in our example).

{% highlight bash %}
dd if=/dev/zero of=/dev/sdb bs=1M count=1
sync
mkudffs --blocksize=512 --media-type=hd /dev/sdb
sync
{% endhighlight %}

Then insert the new drive into your Mac OS machine. It will be mounted as "LinuxUDF". You can then simply rename the
drive.

Mounting a UDF drive at a fixed mount point in Mac OS X
=======================================================

If you use a removable drive on a Mac OS machine frequently (or permanently) it would be nice to mount it at a fixed
location rather than under <tt>/Volume/drivename</tt>. Mac OS still has an fstab-mechanism, but the way to edit the file differs
from Linux. Also, since our UDF does not have a UUID, we will to identify it using a label, so make sure to give a
unique name to each of your UDF-formatted drives.

Eject the UDF drive you renamed in the earlier step. Open the Terminal and start vifs:
{% highlight bash %}
sudo vifs
{% endhighlight %}

Add a line like this to the empty fstab file:
{% highlight bash %}
LABEL=JF64GB  /Users/jojo/mnt/jf64gb  udf rw,auto
{% endhighlight %}

When you insert the drive into your Mac, it will auto-mount at the given mountpoint. It will still show up as a
removable drive on your desktop, and you can still eject it like you did before.

Open problems
=============

First of all, I haven't actually tested whether the UDF drive I created also works on Windows. But given the age and 
pervasion of the UDF standard, I'd be inclined to chalk it up to Windows if it didn't work.

My biggest concern with this setup is that there currently is no Open Source platform-interoperable way to do full-disk
encryption (FDE). Ever since Truecrypt shut down, there isn't even a way to do it between Mac OS and Linux, though both
have very mature FDE solutions builtin. You could use [encfs](https://github.com/vgough/encfs) which is a FUSE-based filesystem
which encrypts both the content and the filenames (but leaves the directory structure visible). encfs is availabe in
most Linux distributions and in homebrew.

Update - January 2014
=====================

I've since experienced a scenario where a UDF-drive on my Linux machine
exhibited some really strange behaviour during writes (via rsync for example),
resulting in a 100% CPU load of the process doing the writing. Since I did not
have the time to investigate I simply switched that disk back to ext4 for now.

References
==========

* [UDF and fstab without UUID](http://osquestions.com/unix-linux/35973/udf-and-fstab-no-uuid)
* [Creating UDF filesystem using mkudffs](http://tanguy.ortolo.eu/blog/article93/usb-udf)
* [Arch Linux on Disk Encryption](https://wiki.archlinux.org/index.php/disk_encryption#compatibility_.26_prevalence)

