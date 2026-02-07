---
layout: default
title: Home
nav_order: 1
---

<div class="page-header">
<h1 class="page-title">Teek API Documentation</h1>
{% include search.html %}
</div>

Tcl/Tk interface for Ruby (8.6+ and 9.x).

## Quick Links

- [Teek Module](/api/Teek/) - Main entry point

## Getting Started

```ruby
require 'teek'

app = Teek::App.new
app.tcl_eval('button .b -text "Hello" -command exit')
app.tcl_eval('pack .b')
app.tcl_eval('tkwait window .')
```

## Search

Use the search box above to find classes, modules, and methods.
