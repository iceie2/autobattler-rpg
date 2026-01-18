from pathlib import Path

def generate(frames_path='assets/sprites/Warrior_PN.frames.tres', cols=13, rows=21, w=64, h=64, img_path='res://assets/sprites/Warrior_PN.png'):
    # Disabled: project uses shape-only visuals. Keep this helper for manual use only.
    lines=[]
    lines.append('[gd_resource type="SpriteFrames" load_steps=1 format=3]')
    lines.append('[ext_resource path="%s" type="Texture2D" id=1]'%img_path)
    sub_id=2
    anim_names=["IdleSouth","IdleEast","IdleNorth","IdleWest","WalkSouth","WalkEast","WalkNorth","WalkWest"]
    frames_per_anim=[]
    for r in range(rows):
        row_ids=[]
        for c in range(cols):
            lines.append('[sub_resource type="AtlasTexture" id=%d]'%sub_id)
            lines.append('atlas = ExtResource( 1 )')
            lines.append('region = Rect2( %d, %d, %d, %d )'%(c*w, r*h, w, h))
            row_ids.append(sub_id)
            sub_id+=1
        frames_per_anim.append(row_ids)
    lines.append('[resource]')
    lines.append('animations = {')
    for r,row in enumerate(frames_per_anim):
        name = anim_names[r] if r < len(anim_names) else ('Anim'+str(r))
        ids = ', '.join('SubResource( %d )'%i for i in row)
        lines.append('"%s": [ %s ],'% (name, ids))
    lines.append('}')
    lines.append('animation_speed = {}')
    lines.append('animation_loop = {}')
    Path(frames_path).write_text('\n'.join(lines))
    print('Wrote', frames_path, 'frames:', cols, 'x', rows, 'frame', w, 'x', h)

if __name__ == '__main__':
    generate()
