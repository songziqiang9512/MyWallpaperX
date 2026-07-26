#!/usr/bin/env python3
"""按配方向 OpenAI 图像 API 请求粒子纹理素材，落盘到 --out。开发期资产工具，不参与构建。

gpt-image-2 不支持 background=transparent，因此配方按用途指定纯色背景：
  - 发光类（火焰/烟雾/闪电/光晕）用纯黑底，灰度即 alpha，与官方 fmt=9 单通道语义一致；
  - 实体类（叶片/花瓣）用纯白底，后续由 scene_particle_texture_matte.py 抠图。

用法：
  export MYWALLPAPERX_IMAGE_API_KEY=sk-...
  python3 script/scene_particle_texture_ai.py --recipe rosepetals --n 4
  python3 script/scene_particle_texture_ai.py --list
  # 自建/代理端点：--base-url https://your-proxy/v1
"""
import argparse
import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

DEFAULT_BASE_URL = 'https://api.openai.com/v1'
DEFAULT_MODEL = 'gpt-image-2'
KEY_ENV = ('MYWALLPAPERX_IMAGE_API_KEY', 'OPENAI_API_KEY')

# 每条配方对应一个待补的内置纹理 key。prompt 描述取自官方同名纹理的可观测事实
# （形态、配色、背景），不含官方像素或私有资产。
RECIPES = {
    'rosepetals': dict(
        key='particle/nature/rosepetals', size='1024x1024', background='white',
        prompt=(
            'A single fresh pink rose petal, photographed flat from directly above on a '
            'pure white seamless background, studio softbox lighting, no shadow, no props. '
            'The petal is soft pink fading to near-white at the base, with faint darker pink '
            'veining and a slightly curled irregular edge. Sharp focus, entire petal visible '
            'and centered, filling most of the frame. Photorealistic macro photography.'),
    ),
    'oakleaf': dict(
        key='particle/nature/leaves7', size='1024x1024', background='white',
        prompt=(
            'A single green oak leaf (Quercus robur), photographed flat from directly above '
            'on a pure white seamless background, even studio lighting, no shadow. Deeply '
            'lobed rounded margins, visible pinnate venation, fresh mid-green upper surface '
            'with subtle yellow-green highlights along the midrib. Sharp focus, whole leaf '
            'visible and centered including the short stalk. Photorealistic botanical '
            'specimen photography.'),
    ),
    'oakleaf_autumn': dict(
        key='particle/nature/leaves8', size='1024x1024', background='white',
        prompt=(
            'A single oak leaf (Quercus robur) turning autumn colour, photographed flat from '
            'directly above on a pure white seamless background, even studio lighting, no '
            'shadow. Deeply lobed margins, visible venation, yellow-green blade with olive '
            'and light brown mottling. Sharp focus, whole leaf visible and centered. '
            'Photorealistic botanical specimen photography.'),
    ),
    'smoke': dict(
        key='particle/smoke/smoke2', size='1024x1024', background='black',
        prompt=(
            'A single dense billowing smoke puff isolated on a pure black background, '
            'lit from the front so the smoke reads bright white-grey with soft internal '
            'shading and rounded cauliflower lobes. The puff is roughly circular, centered, '
            'fills most of the frame, and fades to black at the edges with wispy tendrils. '
            'No text, no ground plane, no light source visible. Photorealistic.'),
    ),
    'fire': dict(
        key='particle/fire/fire1', size='1024x1024', background='black',
        prompt=(
            'A single thin turbulent flame tongue isolated on a pure black background, '
            'monochrome white-hot, rising vertically with wispy filaments and a sparse '
            'broken structure rather than a solid blob. Centered, fading to pure black at '
            'the frame edges. No logs, no ground, no coloured cast. Photorealistic '
            'high-speed photography.'),
    ),
}


def api_key(explicit):
    if explicit:
        return explicit
    for name in KEY_ENV:
        value = os.environ.get(name)
        if value:
            return value
    sys.exit(f'缺少 API key：设置 {KEY_ENV[0]} 环境变量，或用 --api-key 传入')


def request_images(base_url, key, model, prompt, size, count, quality, timeout):
    """POST /images/generations，返回 base64 图片列表。响应形如 {"data":[{"b64_json":...}]}。"""
    body = json.dumps(dict(model=model, prompt=prompt, size=size, n=count,
                           quality=quality)).encode()
    req = urllib.request.Request(
        f'{base_url.rstrip("/")}/images/generations', data=body, method='POST',
        headers={'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode('utf-8', 'replace')[:600]
        sys.exit(f'HTTP {error.code}: {detail}')
    except urllib.error.URLError as error:
        sys.exit(f'请求失败: {error.reason}')
    items = payload.get('data') or []
    if not items:
        sys.exit(f'响应无图片数据: {json.dumps(payload)[:400]}')
    out = []
    for item in items:
        blob = item.get('b64_json')
        if not blob:
            sys.exit('响应缺少 b64_json（该端点可能返回 url，本工具只支持 b64_json）')
        out.append(base64.b64decode(blob))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--recipe', help=f'配方名，可选: {", ".join(sorted(RECIPES))}')
    parser.add_argument('--prompt', help='直接给 prompt，绕过配方')
    parser.add_argument('--list', action='store_true', help='列出配方后退出')
    parser.add_argument('--out', default='/tmp/mwx_assets/ai', help='输出目录')
    parser.add_argument('--base-url', default=os.environ.get('MYWALLPAPERX_IMAGE_BASE_URL',
                                                             DEFAULT_BASE_URL))
    parser.add_argument('--api-key')
    parser.add_argument('--model', default=DEFAULT_MODEL)
    parser.add_argument('--size', default=None, help='默认取配方值，否则 1024x1024')
    parser.add_argument('--quality', default='high', choices=['low', 'medium', 'high', 'auto'])
    parser.add_argument('--n', type=int, default=1, help='单次生成张数')
    parser.add_argument('--timeout', type=float, default=300)
    args = parser.parse_args()

    if args.list:
        for name, recipe in sorted(RECIPES.items()):
            print(f'{name:18s} -> {recipe["key"]:30s} {recipe["size"]:>10s} '
                  f'{recipe["background"]}底')
        return 0

    if args.prompt:
        prompt, size, stem = args.prompt, args.size or '1024x1024', 'custom'
    else:
        if args.recipe not in RECIPES:
            parser.error(f'--recipe 需为: {", ".join(sorted(RECIPES))}（或用 --prompt）')
        recipe = RECIPES[args.recipe]
        prompt, size, stem = recipe['prompt'], args.size or recipe['size'], args.recipe

    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f'模型 {args.model} / {size} / quality={args.quality} / n={args.n}')
    started = time.monotonic()
    images = request_images(args.base_url, api_key(args.api_key), args.model,
                            prompt, size, args.n, args.quality, args.timeout)
    existing = len(list(out_dir.glob(f'{stem}_*.png')))
    written = []
    for offset, blob in enumerate(images):
        path = out_dir / f'{stem}_{existing + offset:02d}.png'
        path.write_bytes(blob)
        written.append(path)
        print(f'  {len(blob) / 1e6:5.2f}MB  {path}')
    (out_dir / f'{stem}_prompt.txt').write_text(prompt + '\n')
    print(f'{len(written)} 张，用时 {time.monotonic() - started:.1f}s')
    return 0


if __name__ == '__main__':
    sys.exit(main())
