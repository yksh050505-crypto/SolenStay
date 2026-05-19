// Firebase Messaging Service Worker
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCHiZRx45N4OhRGLK27fdnqPtfmug8g500',
  authDomain: 'solenstay-74f8e.firebaseapp.com',
  projectId: 'solenstay-74f8e',
  storageBucket: 'solenstay-74f8e.firebasestorage.app',
  messagingSenderId: '263114028567',
  appId: '1:263114028567:web:63dba99381195fa387ce52',
});

const messaging = firebase.messaging();

// 백그라운드 알림 처리
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'SolenStay';
  const body = payload.notification?.body || '';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  });
});
