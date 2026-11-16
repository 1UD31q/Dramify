const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('dotahelperr', {
  version: process.env.npm_package_version || '0.1.0',
});
