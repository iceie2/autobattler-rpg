# Traveling Merchant art provenance and prompts

Created with the built-in Codex imagegen tool (two calls). No API keys or paid external generation service were configured or used. Originals remain in the owner's Codex generated_images directory. Existing production art was not overwritten.

## Assets

- `room.png`: RGB PNG, 1672×941, approximately 16:9. Opaque painterly room without merchant, displayed across the 1920×1080 design canvas with aspect-cover scaling. The right merchandise region is deliberately quiet.
- `merchant.png`: RGBA PNG, 1158×1359. Alpha verified to span 0–255. Hooded goblin, hands and a small counter form one independently animated layer. Displayed in a 490×570 box in the left column, anchored at design coordinate (36, 240).

Room source: `C:/Users/iceie/.codex/generated_images/01a0e211-86c4-75a3-b8a5-799b68a697bb/exec-26b5b11a-181e-432d-82b6-ad450bb2fe06.png`

Merchant source: `C:/Users/iceie/.codex/generated_images/01a0e211-86c4-75a3-b8a5-799b68a697bb/exec-6b1eb61e-cc0d-4b02-97df-53d8b74284a5.png`

## Room prompt

Use case: stylized-concept. Create a production game background, 1920x1080 landscape 16:9, painterly fantasy cozy goblin trading post inside weathered wooden caravan. Rich walnut wood, aged brass, amber lanterns, subtle teal evening light through left side window. NO characters: merchant supplied as separate layer. Compose for UI: left 28 percent has small counter at y=760, coin chest, potion bottles, hanging curios, travel-worn shelves, empty space for hooded goblin behind counter at x=280 y=500. Right 72 percent broad dark quiet walnut surfaces with very subdued detail for merchandise UI overlay. Top 110px and bottom 110px quiet for live header/footer. View straight-on interior, rich crafted painterly game art, inviting warm atmosphere, no text prices cards buttons lettering or UI. Save image as local file for game integration.

## Merchant prompt

Input reference: the generated room above (style and lighting only).

Use case stylized-concept. Reference image is STYLE AND LIGHTING REFERENCE ONLY. Create a separate game merchant cutout asset on genuinely transparent alpha background, portrait aspect, no room/backdrop. Expressive mischievous green goblin merchant in worn brown hood with aged brass trinkets, big pointed ears, strong readable silhouette, welcoming sly smile. Waist-up facing player, hands resting on a narrow small walnut countertop INCLUDED IN CUTOUT at bottom edge so merchant appears behind the counter. Amber lantern light front/right and subtle teal edge light left. Painterly fantasy exactly matching reference room. Complete hood, ears, arms, hands and small counter, nothing cropped, transparent margins, no lettering text cards price tags UI or buttons. Goblin fills most of portrait, head large and expressive. This will be rendered 460px wide by 540px high in left 28% of game shop.

Both generated layers are integrated. Font, text, cards, prices, controls, focus rings and lantern-glow animation are implemented in Godot, not painted into the images.
