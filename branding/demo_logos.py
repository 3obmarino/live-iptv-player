"""Invented channel logos for the demo build (emulator test + website shots).
Run: python3 branding/demo_logos.py  -> branding/demo-logos/demo<N>.png"""
from PIL import Image, ImageDraw, ImageFont
import os

D = '/usr/share/fonts/truetype/dejavu/'
BOLD, COND, SERIF, OBL = D+'DejaVuSans-Bold.ttf', D+'DejaVuSansCondensed-Bold.ttf', D+'DejaVuSerif-Bold.ttf', D+'DejaVuSans-BoldOblique.ttf'
S = 4  # supersample

# (text, style, colour, font) in the demo channel order
LOGOS = [
    ('N1', 'circle', '#E63946', BOLD), ('N2', 'circle', '#457B9D', BOLD),
    ('KØ', 'square', '#2A9D8F', BOLD), ('KV', 'square', '#E76F51', BOLD),
    ('FJORD', 'word', '#4CC9F0', COND), ('HYGGE\nHD', 'pill2', '#F4A261', BOLD),
    ('7', 'circle', '#3A86FF', SERIF), ('LYNGBY', 'bar', '#06D6A0', COND),
    ('AROS', 'outline', '#FFBE0B', BOLD), ('S+', 'square', '#8338EC', BOLD),
    ('SPORT\n1', 'pill2', '#D62828', BOLD), ('SPORT\n2', 'pill2', '#1D3557', BOLD),
    ('X', 'circle', '#F72585', OBL), ('ARENA', 'bar', '#FB5607', COND),
    ('GOAL', 'word', '#38B000', OBL), ('R+', 'square', '#E5383B', OBL),
    ('TENNIS', 'bar', '#9EF01A', COND), ('FN', 'outline', '#FF006E', BOLD),
    ('W24', 'square', '#0077B6', BOLD), ('NN', 'circle', '#023E8A', SERIF),
    ('BIZ', 'outline', '#2EC4B6', BOLD), ('WX', 'circle', '#48CAE4', BOLD),
    ('KIDS', 'word', '#FF5D8F', BOLD), ('CW', 'circle', '#FFB703', BOLD),
    ('JR', 'square', '#7209B7', BOLD), ('TOON', 'word', '#F15BB5', OBL),
    ('PW', 'circle', '#2D6A4F', BOLD), ('SCI', 'outline', '#00B4D8', BOLD),
    ('HV', 'square', '#9C6644', SERIF), ('DEEP', 'bar', '#0096C7', COND),
    ('SPACE', 'word', '#C77DFF', COND), ('MX', 'square', '#495057', BOLD),
]

def fit_font(draw, text, path, box_w, box_h, start):
    size = start
    while size > 8:
        f = ImageFont.truetype(path, size)
        l, t, r, b = draw.multiline_textbbox((0, 0), text, font=f, align='center', spacing=size // 8)
        if r - l <= box_w and b - t <= box_h:
            return f, (l, t, r, b)
        size -= 4
    return f, (l, t, r, b)

def centre_text(draw, text, path, cx, cy, box_w, box_h, fill, start):
    f, (l, t, r, b) = fit_font(draw, text, path, box_w, box_h, start)
    draw.multiline_text((cx - (r + l) / 2, cy - (b + t) / 2), text, font=f, fill=fill,
                        align='center', spacing=f.size // 8)

def make(text, style, col, font):
    W = H = 256 * S
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = W // 2
    if style == 'circle':
        d.ellipse((20*S, 20*S, W-20*S, H-20*S), fill=col)
        centre_text(d, text, font, c, c, 150*S, 120*S, 'white', 150*S)
    elif style == 'square':
        d.rounded_rectangle((24*S, 24*S, W-24*S, H-24*S), radius=44*S, fill=col)
        centre_text(d, text, font, c, c, 160*S, 130*S, 'white', 150*S)
    elif style == 'outline':
        d.rounded_rectangle((26*S, 62*S, W-26*S, H-62*S), radius=26*S, outline=col, width=14*S)
        centre_text(d, text, font, c, c, 160*S, 90*S, col, 120*S)
    elif style == 'pill2':
        d.rounded_rectangle((14*S, 52*S, W-14*S, H-52*S), radius=76*S, fill=col)
        centre_text(d, text, font, c, c, 170*S, 120*S, 'white', 90*S)
    elif style == 'bar':
        d.rounded_rectangle((16*S, 92*S, W-16*S, H-92*S), radius=14*S, fill=col)
        centre_text(d, text, font, c, c, 200*S, 54*S, 'white', 80*S)
    else:  # word
        centre_text(d, text, font, c, c - 10*S, 220*S, 110*S, col, 140*S)
        d.rounded_rectangle((70*S, 178*S, W-70*S, 190*S), radius=6*S, fill=col)
    return im.resize((256, 256), Image.LANCZOS)

out = os.path.join(os.path.dirname(__file__), 'demo-logos')
os.makedirs(out, exist_ok=True)
for i, (t, st, col, f) in enumerate(LOGOS):
    make(t, st, col, f).save(os.path.join(out, f'demo{i}.png'), optimize=True)
print(len(LOGOS), 'logos')
