from PIL import Image, ImageEnhance
import os
import random

# Use the existing warrior sprite
base_sprite = "assets/sprites/Warrior_PN.png"

def generate_random_character(character_id):
    # Load base image
    base = Image.open(base_sprite).convert("RGBA")
    
    # Apply random color tint
    enhancer = ImageEnhance.Color(base)
    color_factor = random.uniform(0.5, 1.5)
    base = enhancer.enhance(color_factor)
    
    # Apply brightness variation
    bright_enhancer = ImageEnhance.Brightness(base)
    brightness_factor = random.uniform(0.8, 1.2)
    base = bright_enhancer.enhance(brightness_factor)
    
    # Save
    base.save(f"generated/character_{character_id:04d}.png")
    
    # Also save a metadata file
    with open(f"generated/character_{character_id:04d}.txt", "w") as f:
        f.write(f"Color factor: {color_factor}\nBrightness: {brightness_factor}")

# Generate 100 characters
os.makedirs("generated", exist_ok=True)
for i in range(100):
    generate_random_character(i)
    if i % 10 == 0:
        print(f"Generated {i} characters...")

print("Done!")