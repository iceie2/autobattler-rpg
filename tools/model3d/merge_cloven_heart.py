import runpy, sys
sys.argv = ['glb_merge_anims.py', 'tools/model3d/cloven-heart-stage',
            'assets/3d pipeline/enemy/cloven_heart/cloven_heart_v001.glb', '--no-tex-resize']
runpy.run_path('tools/model3d/glb_merge_anims.py', run_name='__main__')
