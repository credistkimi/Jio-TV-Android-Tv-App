import os
from PIL import Image, ImageDraw, ImageFont

def create_jiotv_icon(size=512):
    # High-resolution master icon
    master_size = 1024
    img = Image.new('RGBA', (master_size, master_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Gradient-like background circular disk
    # Center circle
    center = master_size // 2
    radius = int(master_size * 0.46)

    # Outer glow / rim
    draw.ellipse([center - radius - 8, center - radius - 8, center + radius + 8, center + radius + 8], 
                 fill=(0, 110, 245, 120))
    # Main Jio brand blue circle (#0A2885)
    draw.ellipse([center - radius, center - radius, center + radius, center + radius], 
                 fill=(10, 40, 133, 255))
    # Inner subtle radial highlight
    inner_r = int(radius * 0.94)
    draw.ellipse([center - inner_r, center - inner_r - 20, center + inner_r, center + inner_r - 20], 
                 fill=(16, 56, 175, 180))

    # Fonts
    font_bold = "C:/Windows/Fonts/segoeuib.ttf"
    font_jio = ImageFont.truetype(font_bold, 300)
    font_tv = ImageFont.truetype(font_bold, 130)
    font_plus = ImageFont.truetype(font_bold, 100)

    # Render "Jio" in white
    # Measure text bounding box
    jio_bbox = draw.textbbox((0, 0), "Jio", font=font_jio)
    jio_w = jio_bbox[2] - jio_bbox[0]
    jio_h = jio_bbox[3] - jio_bbox[1]
    
    jio_x = (master_size - jio_w) // 2
    jio_y = (master_size - jio_h) // 2 - 80

    # Draw "Jio" shadow and text
    draw.text((jio_x + 4, jio_y + 4), "Jio", fill=(0, 20, 70, 160), font=font_jio)
    draw.text((jio_x, jio_y), "Jio", fill=(255, 255, 255, 255), font=font_jio)

    # Bottom Pill for "TV +"
    pill_w = 420
    pill_h = 130
    pill_x = (master_size - pill_w) // 2
    pill_y = jio_y + jio_h + 90

    # Pill background (deep red with rounded corners)
    draw.rounded_rectangle([pill_x, pill_y, pill_x + pill_w, pill_y + pill_h], 
                           radius=65, fill=(229, 9, 20, 255))
    
    # TV text in white
    tv_bbox = draw.textbbox((0, 0), "TV", font=font_tv)
    tv_w = tv_bbox[2] - tv_bbox[0]
    tv_h = tv_bbox[3] - tv_bbox[1]
    tv_x = pill_x + 65
    tv_y = pill_y + (pill_h - tv_h) // 2 - 12
    draw.text((tv_x, tv_y), "TV", fill=(255, 255, 255, 255), font=font_tv)

    # "+" badge
    plus_bbox = draw.textbbox((0, 0), "+", font=font_plus)
    plus_w = plus_bbox[2] - plus_bbox[0]
    plus_h = plus_bbox[3] - plus_bbox[1]
    plus_x = tv_x + tv_w + 35
    plus_y = pill_y + (pill_h - plus_h) // 2 - 14
    # Gold / Amber '+' badge for VIP/Plus
    draw.text((plus_x, plus_y), "+", fill=(255, 215, 0, 255), font=font_plus)

    # Resize to target size using high-quality Lanczos filter
    return img.resize((size, size), Image.Resampling.LANCZOS)

def create_leanback_banner(width=640, height=360):
    # 16:9 Leanback banner for Amazon Fire TV & Android TV
    banner = Image.new('RGBA', (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(banner)

    # Deep gradient background (#050D1A to #0D2246)
    for y in range(height):
        ratio = y / height
        r = int(5 * (1 - ratio) + 13 * ratio)
        g = int(13 * (1 - ratio) + 34 * ratio)
        b = int(26 * (1 - ratio) + 70 * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

    # Radial subtle glow in center-left
    for radius in range(180, 0, -5):
        alpha = int(45 * (1 - radius / 180.0))
        draw.ellipse([150 - radius, height // 2 - radius, 150 + radius, height // 2 + radius], 
                     fill=(0, 110, 245, alpha))

    # Draw iconic Jio circle emblem on left
    emblem_size = 180
    emblem = create_jiotv_icon(emblem_size)
    banner.paste(emblem, (60, (height - emblem_size) // 2), emblem)

    # Typography on right
    font_bold = "C:/Windows/Fonts/segoeuib.ttf"
    font_regular = "C:/Windows/Fonts/segoeui.ttf"
    title_font = ImageFont.truetype(font_bold, 76)
    sub_font = ImageFont.truetype(font_bold, 24)

    text_x = 270
    title_y = 100

    # Title: JioTV+
    draw.text((text_x, title_y), "Jio", fill=(255, 255, 255, 255), font=title_font)
    jio_bbox = draw.textbbox((0, 0), "Jio", font=title_font)
    jio_w = jio_bbox[2] - jio_bbox[0]

    draw.text((text_x + jio_w + 10, title_y), "TV", fill=(255, 255, 255, 255), font=title_font)
    tv_bbox = draw.textbbox((0, 0), "TV", font=title_font)
    tv_w = tv_bbox[2] - tv_bbox[0]

    draw.text((text_x + jio_w + tv_w + 16, title_y), "+", fill=(255, 51, 68, 255), font=title_font)

    # Subtitle badge: LIVE TV • GUIDE • CATCHUP
    sub_y = title_y + 90
    draw.rounded_rectangle([text_x, sub_y, text_x + 310, sub_y + 44], 
                           radius=8, fill=(0, 68, 187, 180), outline=(0, 140, 255, 220), width=1)
    draw.text((text_x + 18, sub_y + 8), "LIVE TV  •  EPG GUIDE", fill=(230, 240, 255, 255), font=sub_font)

    return banner

def main():
    base_res = "D:/Download/JIO TV/jio_tv_plus_flutter/android/app/src/main/res"
    os.makedirs(f"{base_res}/drawable", exist_ok=True)
    os.makedirs(f"{base_res}/drawable-xhdpi", exist_ok=True)
    os.makedirs("D:/Download/JIO TV/jio_tv_plus_flutter/assets/images", exist_ok=True)

    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    print("Generating Mipmap Icons...")
    for folder, sz in sizes.items():
        icon = create_jiotv_icon(sz)
        dest = os.path.join(base_res, folder, "ic_launcher.png")
        icon.save(dest, "PNG")
        print(f"  -> Saved {dest} ({sz}x{sz})")

    # High-res 512x512 app logo for assets
    app_icon = create_jiotv_icon(512)
    app_icon.save("D:/Download/JIO TV/jio_tv_plus_flutter/assets/images/jiotv_plus_logo.png", "PNG")
    print("  -> Saved assets/images/jiotv_plus_logo.png (512x512)")

    # 16:9 TV Banners for Fire TV Leanback
    print("Generating Leanback Banners...")
    banner_320 = create_leanback_banner(320, 180)
    banner_640 = create_leanback_banner(640, 360)

    banner_320.save(os.path.join(base_res, "drawable", "banner.png"), "PNG")
    banner_320.save(os.path.join(base_res, "drawable-xhdpi", "banner.png"), "PNG")
    banner_640.save("D:/Download/JIO TV/jio_tv_plus_flutter/assets/images/banner.png", "PNG")
    print(f"  -> Saved drawable/banner.png (320x180)")
    print(f"  -> Saved drawable-xhdpi/banner.png (320x180)")
    print(f"  -> Saved assets/images/banner.png (640x360)")
    print("All logos and banners generated successfully!")

if __name__ == "__main__":
    main()
