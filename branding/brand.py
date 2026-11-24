import random
G='#00FF41'; K='#0B0C0B'; D='#00170A'

def rain_icon(x=0, y=0, s=100, bg=True, rx=22):
    """Code-rain TV icon in a 100x100 box, placed at x,y scaled to s."""
    k = s / 100
    inner = (f'<rect width="100" height="100" rx="{rx}" fill="{K}"/>' if bg else '') + f'''
<rect x="18" y="30" width="64" height="48" rx="8" fill="none" stroke="{G}" stroke-width="5"/>
<g stroke="{G}" stroke-width="5" stroke-linecap="round">
<path d="M31 38v22"/><path d="M41 38v8" opacity=".5"/><path d="M41 54v14"/>
<path d="M50 38v30" opacity=".75"/><path d="M59 38v12"/><path d="M59 58v10" opacity=".5"/>
<path d="M69 38v18" opacity=".75"/></g>
<path d="M38 16l12 12 12-12" fill="none" stroke="{G}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'''
    return f'<g transform="translate({x} {y}) scale({k})">{inner}</g>'

def rain_bg(w, h, seed=7, cols=34, op=0.16):
    r = random.Random(seed)
    out = []
    step = w / cols
    for i in range(cols):
        cx = step * (i + 0.5)
        yy = -r.uniform(0, h * 0.6)
        while yy < h:
            ln = r.uniform(h * 0.08, h * 0.35)
            o = r.uniform(op * 0.3, op)
            out.append(f'<path d="M{cx:.1f} {yy:.1f}v{ln:.1f}" stroke="{G}" stroke-width="{step*0.28:.1f}" stroke-linecap="round" opacity="{o:.2f}"/>')
            yy += ln + r.uniform(h * 0.06, h * 0.25)
    return ''.join(out)

FONT = "font-family=\"Inter, 'Segoe UI', sans-serif\" font-weight=\"700\""

def banner_a(w=320, h=180):
    # icon + wordmark, faint rain behind
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 320 180">
<rect width="320" height="180" fill="{K}"/>{rain_bg(320,180,op=0.13)}
<rect x="22" y="44" width="92" height="92" rx="20" fill="{K}"/>
{rain_icon(22, 44, 92)}
<text x="128" y="106" {FONT} font-size="44" fill="#FFFFFF" letter-spacing="-1">Live<tspan fill="{G}" dx="8">TV</tspan></text>
</svg>'''

def banner_b(w=320, h=180):
    # wordmark only, rain full-bleed, soft dark band behind the text
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 320 180">
<rect width="320" height="180" fill="{K}"/>{rain_bg(320,180,seed=3,cols=40,op=0.42)}
<rect x="0" y="58" width="320" height="64" fill="{K}" opacity=".82"/>
<text x="151" y="106" text-anchor="end" {FONT} font-size="48" fill="#FFFFFF" letter-spacing="-1">Live</text><text x="165" y="106" {FONT} font-size="48" fill="{G}" letter-spacing="-1">TV</text>
</svg>'''

def app_icon(size=512, rx=22):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100">{rain_icon(0,0,100,rx=rx)}</svg>'
