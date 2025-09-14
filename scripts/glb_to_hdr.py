"""
GLB 场景转 HDR 环境贴图的 Blender 脚本
使用方法：在 Blender 中运行此脚本
"""

import bpy
import bmesh
import os
from mathutils import Vector

def clear_scene():
    """清空场景"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def import_glb(filepath):
    """导入 GLB 文件"""
    bpy.ops.import_scene.gltf(filepath=filepath)
    print(f"已导入: {filepath}")

def setup_camera_for_hdri():
    """设置全景相机"""
    # 添加相机
    bpy.ops.object.camera_add(location=(0, 0, 0))
    camera = bpy.context.active_object
    
    # 设置为全景相机
    camera.data.type = 'PANO'
    camera.data.cycles.panorama_type = 'EQUIRECTANGULAR'
    
    # 设置为活动相机
    bpy.context.scene.camera = camera
    
    return camera

def convert_lights_to_emissive():
    """将灯光转换为发光材质"""
    for obj in bpy.context.scene.objects:
        if obj.type == 'LIGHT':
            light = obj.data
            
            # 创建发光球体代替点光源
            if light.type == 'POINT':
                bpy.ops.mesh.primitive_uv_sphere_add(
                    radius=0.1, 
                    location=obj.location
                )
                sphere = bpy.context.active_object
                
                # 创建发光材质
                mat = bpy.data.materials.new(name=f"Emissive_{obj.name}")
                mat.use_nodes = True
                nodes = mat.node_tree.nodes
                
                # 清除默认节点
                nodes.clear()
                
                # 添加发光节点
                emission = nodes.new(type='ShaderNodeEmission')
                output = nodes.new(type='ShaderNodeOutputMaterial')
                
                # 设置发光强度和颜色
                emission.inputs['Color'].default_value = (*light.color, 1.0)
                emission.inputs['Strength'].default_value = light.energy * 100
                
                # 连接节点
                mat.node_tree.links.new(emission.outputs['Emission'], output.inputs['Surface'])
                
                # 应用材质
                sphere.data.materials.append(mat)
                
                print(f"转换点光源: {obj.name}")

def setup_render_settings(width=2048, height=1024):
    """设置渲染参数"""
    scene = bpy.context.scene
    
    # 使用 Cycles 渲染引擎
    scene.render.engine = 'CYCLES'
    
    # 设置分辨率
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    
    # 设置文件格式
    scene.render.image_settings.file_format = 'HDR'
    scene.render.image_settings.color_mode = 'RGB'
    
    # Cycles 设置
    scene.cycles.samples = 128  # 移动端可以降低到 64
    scene.cycles.use_denoising = True
    
    print("渲染设置完成")

def render_hdri(output_path):
    """渲染 HDR 环境贴图"""
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    print(f"HDR 已保存到: {output_path}")

def glb_to_hdr(glb_path, output_path, resolution=(2048, 1024)):
    """主函数：GLB 转 HDR"""
    print("开始转换 GLB 到 HDR...")
    
    # 1. 清空场景
    clear_scene()
    
    # 2. 导入 GLB
    import_glb(glb_path)
    
    # 3. 转换灯光为发光材质
    convert_lights_to_emissive()
    
    # 4. 设置全景相机
    setup_camera_for_hdri()
    
    # 5. 设置渲染参数
    setup_render_settings(resolution[0], resolution[1])
    
    # 6. 渲染
    render_hdri(output_path)
    
    print("转换完成！")

# 使用示例
if __name__ == "__main__":
    # 设置文件路径
    glb_file = "path/to/your/scene.glb"  # 替换为你的 GLB 文件路径
    hdr_output = "path/to/output/environment.hdr"  # 输出 HDR 路径
    
    # 执行转换（移动端推荐使用较小分辨率）
    glb_to_hdr(glb_file, hdr_output, resolution=(1024, 512))