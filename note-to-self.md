## Where I last left things

This feature gave me some real headaches. I tried for weeks to get it working with the help of different LLMs and coding agents but to no avail. 

This commit: 

```bash
commit 24e117b16f044ee59ba6255c60db7d33a54b429b
Author: Albot Goodman <albotgoodman@gmail.com>
Date:   Thu Oct 1 23:43:11 2026 +0200
```

That was the last working commit, if I recall correctly. However I didn't see any effect of Headroom. A simple "hi" still took 8'000 tokens in opencode using qwen3-coder:30b. I believed it was due to pytorch not being installed and that it ran on CPU - because my performance was terrible (20 t/s) and I thought the CPU was the bottleneck. 

In this commit: 

```bash
commit 08816bfea2b81017c7f70a0f141c534b9bae0c98
Author: Albot Goodman <albotgoodman@gmail.com>
Date:   Thu Oct 8 23:55:50 2026 +0200
```

I tried fixing it with a separate Dockerfile since pytorch wasn't in the image. However that just resulted in my messages in opencode to be "unauthorized". I tried to implement keys but that's were I left things. 

The commit after that is just to add this documentation for the future me. 