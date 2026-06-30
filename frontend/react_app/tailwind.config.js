/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: "#00FFCC",
        secondary: "#1E1E1E",
        danger: "#FF3366",
        dark: "#121212",
        darkalt: "#1E1E1E",
      },
      fontFamily: {
        sans: ["Outfit", "sans-serif"],
        display: ["Inter", "sans-serif"],
      },
    },
  },
  plugins: [],
}
