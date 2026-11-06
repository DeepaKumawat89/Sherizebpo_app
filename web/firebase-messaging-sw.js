importScripts("https://www.gstatic.com/firebasejs/8.10.1/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.1/firebase-messaging.js");

firebase.initializeApp({
  apiKey: "AIzaSyCrHTxLg2USbEkmBj41mN9U88zcrTBM1V0",
  authDomain: "sherize-bpo.firebaseapp.com",
  projectId: "sherize-bpo",
  storageBucket: "sherize-bpo.firebasestorage.app",
  messagingSenderId: "1008144551131",
  appId: "1:1008144551131:web:b48994be5a8d14475e90fe",
  measurementId: "G-W6SJQTEJM3"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log("[firebase-messaging-sw.js] Received background message ", payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: "/icons/Icon-192.png"
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
