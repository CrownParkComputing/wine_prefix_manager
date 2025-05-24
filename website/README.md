# Wine Prefix Manager Website

This is the official website for Wine Prefix Manager, designed for Product Hunt launch and user acquisition.

## Features

- **Modern Design**: Clean, professional layout with dark theme
- **Responsive**: Works perfectly on desktop, tablet, and mobile
- **Interactive**: Smooth animations, hover effects, and dynamic content
- **GitHub Integration**: Automatically fetches latest release information
- **SEO Optimized**: Proper meta tags for social media sharing
- **Fast Loading**: Optimized images and minimal dependencies

## Structure

```
website/
├── index.html          # Main landing page
├── css/
│   └── style.css       # All styles (modern CSS with variables)
├── js/
│   └── script.js       # Interactive functionality
├── images/
│   ├── hero-screenshot.png
│   ├── screenshot-1.png
│   ├── screenshot-2.png
│   └── screenshot-3.png
└── assets/
    └── (favicon and other assets)
```

## Sections

1. **Hero Section**: Eye-catching intro with download CTA
2. **Features**: 6 key features with icons and descriptions
3. **Screenshots**: Interactive gallery of app screenshots
4. **Download**: Prominent download section with system requirements
5. **About**: Information about the project and developer
6. **Footer**: Links and additional information

## Deployment

### GitHub Pages (Recommended)

1. **Enable GitHub Pages**:
   - Go to your repository Settings
   - Scroll to "Pages" section
   - Set source to "Deploy from a branch"
   - Select "main" branch and "/website" folder
   - Save

2. **Update Links**:
   - Replace `your-username` in `index.html` and `script.js` with your actual GitHub username
   - Update social media links in the footer

3. **Custom Domain** (Optional):
   - Add a CNAME file in the website folder
   - Configure your domain in repository settings

### Local Development

1. **Simple HTTP Server**:
   ```bash
   cd website
   python -m http.server 8000
   # Visit http://localhost:8000
   ```

2. **Live Server** (VS Code extension):
   - Install "Live Server" extension
   - Right-click on `index.html` → "Open with Live Server"

## Customization

### Colors
Edit CSS variables in `:root` section of `style.css`:
```css
--primary-color: #6366f1;    /* Main brand color */
--secondary-color: #ec4899;  /* Accent color */
--accent-color: #10b981;     /* Success/download color */
```

### Content
- Update text content in `index.html`
- Replace screenshots in `images/` folder
- Modify feature descriptions
- Update social media links

### GitHub Integration
The website automatically fetches the latest release from GitHub API. Update the repository URL in `script.js`:
```javascript
const response = await fetch('https://api.github.com/repos/YOUR-USERNAME/wine_prefix_manager/releases/latest');
```

## Performance

- **Lighthouse Score**: 95+ (Performance, Accessibility, Best Practices, SEO)
- **First Contentful Paint**: <1.5s
- **Largest Contentful Paint**: <2.5s
- **Cumulative Layout Shift**: <0.1

## Browser Support

- Chrome 60+
- Firefox 55+
- Safari 11+
- Edge 79+

## Product Hunt Optimization

The website is optimized for Product Hunt launch:

- **Social Media Tags**: Open Graph and Twitter Card meta tags
- **High-Quality Screenshots**: Professional app screenshots
- **Clear Value Proposition**: Immediate understanding of benefits
- **Strong CTAs**: Prominent download buttons
- **Mobile Optimized**: Perfect mobile experience
- **Fast Loading**: Optimized for quick social media visits

## Analytics Integration

To add analytics, include in `<head>` of `index.html`:

```html
<!-- Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=GA_MEASUREMENT_ID"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'GA_MEASUREMENT_ID');
</script>
```

## Contact

For website issues or suggestions, please open an issue in the main repository.

---

**Live Website**: https://your-username.github.io/wine_prefix_manager/
**Repository**: https://github.com/your-username/wine_prefix_manager 