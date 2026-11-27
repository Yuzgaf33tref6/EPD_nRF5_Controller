# 第三方资产说明（Third-party assets）

本目录下的资源来自第三方项目，各自遵循其原始许可证。

## blue_noise_64.png

- 内容：64×64、8 位灰度的蓝噪声（blue noise）排序矩阵，每个像素的取值范围
  0-255，分布均匀（每 32 级约 512 个像素）。用于 `DitherAlgorithm.blueNoise`
  的阈值抖动。
- 来源：`epdoptimize` 1.3.0 中的 `BLUE_NOISE_TEXTURE`（Uint8Array，长度 4096），
  由本仓库的 `tools/extract-blue-noise.mjs` 提取并转成 PNG。
  - 项目主页：https://github.com/paperlesspaper/epdoptimize
  - 许可证：**Apache License 2.0**
- 本仓库整体以 GPL-3.0 发布；Apache-2.0 与 GPL-3.0 兼容（Apache-2.0 许可的代码
  可以并入 GPL-3.0 作品），此处按 Apache-2.0 的要求保留来源与许可说明。
- 改动说明：仅做了「把原始字节序列编码为 PNG」这一封装，数值未做任何修改。

> 说明：本项目没有使用 `epdoptimize` 的任何源码，只提取了这一张公开的噪声纹理
> 数据；误差扩散核（Floyd–Steinberg / Atkinson / Stucki / Jarvis / Burkes /
> Sierra Lite / Shiau-Fan）均为公开的经典算法实现，由本项目独立编写。
