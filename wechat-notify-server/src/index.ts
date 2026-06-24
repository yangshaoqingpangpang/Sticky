import { config, wechatConfigured } from './config.js';
import { load } from './store.js';
import { createServer } from './server.js';
import { startScheduler } from './scheduler.js';

load();
const app = createServer();
startScheduler();
app.listen(config.port, () => {
  console.log(`[wechat-notify] 监听 :${config.port}  微信资质=${wechatConfigured() ? '已配置' : '未配置(占位联调)'}`);
});
