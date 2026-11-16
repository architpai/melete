import pathlib
src = pathlib.Path(__file__).parent
out = src.parent
S = 'xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"'
I = {
 "play": f'<svg class="g" {S}><path d="M5 3.2v9.6l7.5-4.8z"/></svg>',
 "pause": f'<svg class="g" {S}><path d="M4.5 3.5h2.3v9H4.5zM9.2 3.5h2.3v9H9.2z"/></svg>',
 "skip": f'<svg class="g" {S}><path d="M3.5 3.5v9l6.3-4.5zM10.8 3.5h1.8v9h-1.8z"/></svg>',
 "reset": f'<svg class="g s" {S}><path d="M3.3 8a4.7 4.7 0 1 0 1.5-3.4"/><path d="M3.2 2.6v2.6h2.6"/></svg>',
 "cup": f'<svg class="g" {S} style="fill:none;stroke:currentColor;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round;width:13px;height:13px"><path d="M2.5 6h8.5v3.3a3.2 3.2 0 0 1-3.2 3.2H5.7a3.2 3.2 0 0 1-3.2-3.2z"/><path d="M11 7h.9a1.6 1.6 0 0 1 0 3.2H11"/><path d="M5.5 2.5v1.5M8 2.5v1.5"/></svg>',
 "chart": f'<svg class="ico" {S}><path d="M3 13.5V9M8 13.5V3M13 13.5V6.5"/></svg>',
 "gear": f'<svg class="ico" {S}><circle cx="8" cy="8" r="2.2"/><circle cx="8" cy="8" r="4.7"/><path d="M8 1.3v1.9M8 12.8v1.9M1.3 8h1.9M12.8 8h1.9M3.3 3.3l1.3 1.3M11.4 11.4l1.3 1.3M3.3 12.7l1.3-1.3M11.4 4.6l1.3-1.3"/></svg>',
 "plus": f'<svg class="ico" {S} style="width:13px;height:13px"><path d="M8 3v10M3 8h10"/></svg>',
}
R = (f'<svg {S}><rect x="2" y="3" width="12" height="4.2" rx="2.1"/><rect x="2" y="8.8" width="12" height="4.2" rx="2.1"/></svg>'
     f'<svg {S}><path d="M1.8 6.3a9 9 0 0 1 12.4 0M4 8.6a6 6 0 0 1 8 0M6.2 10.9a3 3 0 0 1 3.6 0"/><circle cx="8" cy="13" r=".6" fill="currentColor"/></svg>'
     f'<svg {S} style="width:22px"><rect x=".8" y="4.3" width="12.4" height="7.4" rx="2"/><rect x="2.3" y="5.8" width="8" height="4.4" rx="1" fill="currentColor" stroke="none"/><path d="M14.6 7v2"/></svg>'
     '<span>Mon 16 Nov 10:42</span>')
MB = ('<div class="menubar"><div class="mb-left"><b>Xcode</b><span>File</span><span>Edit</span><span>View</span><span>Find</span>'
      '<span>Navigate</span><span>Editor</span><span>Product</span><span>Debug</span><span>Window</span><span>Help</span></div>'
      f'<div class="mb-right">{R}</div></div>')
MBF = ('<div class="menubar flat"><div class="mb-left"><b>Finder</b><span>File</span><span>Edit</span><span>View</span></div>'
       f'<div class="mb-right">{R}</div></div>')
MBF2 = ('<div class="menubar flat"><div class="mb-left"><b>Finder</b><span>File</span></div>'
        f'<div class="mb-right"><span>10:42</span></div></div>')
css = (src / "style.css").read_text()
def page(body, title):
    for k, v in {"MB": MB, "MBF": MBF, "MBF2": MBF2, **I}.items():
        body = body.replace("{{" + k + "}}", v)
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{title}</title><style>{css}</style></head><body><div class="page">{body}</div></body></html>')
parts = {"notch-collapsed": "Melete notch collapsed", "notch-expanded": "Melete notch expanded", "windows": "Melete windows"}
files = {"notch-collapsed": "collapsed.html", "notch-expanded": "expanded.html", "windows": "windows.html"}
bodies = []
for name, title in parts.items():
    b = (src / files[name]).read_text(); bodies.append(b)
    (out / f"{name}.html").write_text(page(b, title))
(out / "index.html").write_text(page("\n".join(bodies), "Melete mocks"))
print("ok")
