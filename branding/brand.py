import random
G='#00FF41'; K='#0B0C0B'; D='#00170A'

def rain_icon(x=0, y=0, s=100, bg=True, rx=22):
    """TV screen with Matrix code rain and the antenna chevron turned 90 degrees
    into a play arrow. A dark halo knocks the rain out behind the arrow."""
    k = s / 100
    rain = [
        (28, 30, 16, .5),  (28, 52, 18, .85),
        (36, 30, 26, .85), (36, 62, 8, .45),
        (44, 30, 8, .45),  (44, 44, 26, .7),
        (52, 30, 20, .7),  (52, 56, 14, .45),
        (60, 30, 10, .85), (60, 46, 24, .55),
        (68, 30, 28, .6),  (68, 64, 6, .85),
        (74, 34, 14, .4),  (74, 54, 14, .7),
    ]
    cols = ''.join(f'<path d="M{cx} {y0}v{ln}" opacity="{o}"/>' for cx, y0, ln, o in rain)
    inner = (f'<rect width="100" height="100" rx="{rx}" fill="{K}"/>' if bg else '') + f'''
<rect x="18" y="22" width="64" height="56" rx="9" fill="none" stroke="{G}" stroke-width="5"/>
<g stroke="{G}" stroke-width="4" stroke-linecap="round">{cols}</g>
<path d="M41 35l17 15-17 15" fill="none" stroke="{K}" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M41 35l17 15-17 15" fill="none" stroke="{G}" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round"/>'''
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
{rain_icon(22, 44, 92)}
<text x="128" y="106" {FONT} font-size="44" fill="#FFFFFF" letter-spacing="-1">Live<tspan fill="{G}" dx="3">TV</tspan></text>
</svg>'''

def banner_b(w=320, h=180):
    # wordmark only, rain full-bleed, soft dark band behind the text
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 320 180">
<rect width="320" height="180" fill="{K}"/>{rain_bg(320,180,seed=3,cols=40,op=0.42)}
<rect x="0" y="58" width="320" height="64" fill="{K}" opacity=".82"/>
<text x="173" y="106" text-anchor="end" {FONT} font-size="48" fill="#FFFFFF" letter-spacing="-1">Live</text><text x="178" y="106" {FONT} font-size="48" fill="{G}" letter-spacing="-1">TV</text>
</svg>'''

def app_icon(size=512, rx=22):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100">{rain_icon(0,0,100,rx=rx)}</svg>'
