# Xuelong2-DWL代码上传指南

## 一、公开前检查

1. 将ERA5下载脚本及完整请求参数加入仓库。
2. 确认`README.md`中的数据集DOI。
3. 选择代码许可证，例如MIT或BSD-3-Clause。
4. 确认所有MATLAB脚本均通过`project_config.m`读取路径。
5. 不要上传ERA5 NetCDF、166个激光雷达CSV、输出图片或MATLAB临时文件。
6. 不要上传`.cdsapirc`、访问令牌、密码或个人API密钥。

## 二、创建GitHub仓库

1. 登录GitHub。
2. 点击右上角`+`，选择`New repository`。
3. Repository name建议填写`Xuelong2-DWL-Code`。
4. Description可填写：`MATLAB code for ERA5 collocation and technical validation of the Xuelong2-DWL dataset.`
5. 在代码和许可证确认前，可先选择`Private`；正式归档Zenodo前需要改为`Public`。
6. 不要在GitHub网页中自动创建README、`.gitignore`或License，因为本地文件夹中已经包含前两项。
7. 点击`Create repository`。

## 三、上传本地文件夹

最简单的网页上传方法：

1. 进入新建仓库。
2. 点击`uploading an existing file`或`Add file` > `Upload files`。
3. 将本文件夹中的全部文件拖入上传区域，但不要拖入文件夹外的ERA5或激光雷达数据。
4. 提交说明填写`Initial public code release`。
5. 点击`Commit changes`。

如果网页不能完整保留目录结构，建议安装GitHub Desktop，选择`Add an Existing Repository from your Hard Drive`，然后发布该仓库。

## 四、发布v1.0.0

1. 完成代码和说明检查后，将仓库设置为`Public`。
2. 在GitHub仓库右侧点击`Releases`。
3. 点击`Draft a new release`。
4. 创建标签`v1.0.0`。
5. Release title填写`Xuelong2-DWL Code v1.0.0`。
6. Release notes简要列出脚本、MATLAB版本和对应论文。
7. 点击`Publish release`。

## 五、连接Zenodo并生成代码DOI

1. 登录Zenodo，选择使用GitHub账号授权登录。
2. 打开Zenodo的GitHub设置页面。
3. 找到`Xuelong2-DWL-Code`并将开关设为`On`。
4. 如果在连接Zenodo前已经发布GitHub Release，可重新创建一个Release或按Zenodo提示同步。
5. Zenodo会为GitHub Release保存固定快照并生成DOI。
6. 将代码DOI填写回`README.md`、`CODE_AVAILABILITY.md`和论文参考文献。

## 六、论文中的代码说明

论文`Code Availability`应同时提供：

- GitHub地址，用于查看和更新代码；
- Zenodo DOI，用于永久引用论文实际使用的固定版本；
- MATLAB和工具箱版本；
- 软件许可证。
