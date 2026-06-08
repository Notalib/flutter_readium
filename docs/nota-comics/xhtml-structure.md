# Nota Comics XHTML Structure

In-house narrated comic book format, developed by Nota-service.

This is an extention to Readium's webpub+EPUB profile, intended to be used with media overlays or guided navigation.

An example is available in [example](example/nota-comic-page.xhtml).

## Markup.

### figure - the container.

A comic page is a single `figure`-element, which contains one `img`-element with the class `page` and a number of `div`-elements with the class `area`.

```html
<figure>
  <img class="page" id="..." style="..." />

  <div class="area" id="..." style="..."></div>
</figure>
```

A single XHTML document can contain multiple comic book pages.

#### img.page

The full sized comic book page.

| Attribute | Description                                         | Required |
| --------- | --------------------------------------------------- | -------- |
| id        | Element id                                          | yes      |
| style     | CSS properties needed to render the page, see below | yes      |


| CSS property | Description                    | Required |
| ------------ | ------------------------------ | -------- |
| height       | Natural image height in pixels | yes      |
| width        | Natural image width in pixels  | yes      |

When sync narration points to the image, the full page will be shown on screen.

The size information is used to scale rendering and focus on panels.

#### div.area

Each panel has its own `div.area` element. This elemenet positions the panel relative to the image.

| Attribute | Description                                          | Required |
| --------- | ---------------------------------------------------- | -------- |
| id        | Element id                                           | yes      |
| style     | CSS properties needed to render the panel, see below | yes      |


| CSS property | Description                                  | Required |
| ------------ | -------------------------------------------- | -------- |
| top          | Top offset in pixels, relative to the image  | yes      |
| left         | Left offset in pixels, relative to the image | yes      |
| height       | Natural image height in pixels               | yes      |
| width        | Natural image width in pixels                | yes      |

When sync narration points to the area, the size and position information will be used to zoom the portion of the image into view.

## `<head>` section

It is recommended to have charset and viewport defined in your `head`-element:

```html
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta charset="UTF-8" />
  <title>Når tegneserien bliver digital</title>
  <meta name="viewport" content="width=device-width" />
</head>
```

## Example

```xml
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops"
      lang="da">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta charset="UTF-8" />
    <title>Når tegneserien bliver digital</title>
    <meta name="viewport" content="width=device-width" />
    <meta name="dc:identifier" content="dk-nota-50272" />
  </head>
  <body id="d14069302e1">
    <h1 id="h00003">Side 3</h1>

    <figure class="image" id="image0003">
      <img id="hix00003"
           style="height:1747px;width:1240px"
           alt=""
           class="page"
           src="nota-comic-page.jpg" />

      <!-- Panel regions in reading order -->
      <div id="image0003_000" style="left:10px;top:8px;width:558px;height:259px;"    class="area"></div>
      <div id="image0003_001" style="left:10px;top:251px;width:620px;height:426px;"  class="area"></div>
      <div id="image0003_002" style="left:516px;top:14px;width:720px;height:352px;"  class="area"></div>
      <div id="image0003_003" style="left:632px;top:258px;width:601px;height:735px;" class="area"></div>
      <div id="image0003_004" style="left:14px;top:684px;width:625px;height:748px;"  class="area"></div>
      <div id="image0003_005" style="left:4px;top:1444px;width:611px;height:230px;"  class="area"></div>
      <div id="image0003_006" style="left:589px;top:990px;width:648px;height:750px;" class="area"></div>
    </figure>
  </body>
</html>
```
