/*
 * 绘声绘色 网页配置
 * 只部署静态网页、不配云函数时：保持为空。使用者需在页面“设置”里填自己的密钥，
 *   且 DeepSeek、MiniMax 必须允许浏览器直接访问，否则会提示“连不上模型接口”。
 * 部署了云函数 thf-proxy 时：把下面的引号里改成云函数的访问地址（到路径前缀为止，结尾不要加 /api），
 *   例如 'https://你的环境ID.service.tcloudbase.com/thf'
 */
window.THF_API = '';
