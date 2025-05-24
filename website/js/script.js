// Mobile Navigation Toggle
const hamburger = document.querySelector('.hamburger');
const navMenu = document.querySelector('.nav-menu');

hamburger.addEventListener('click', () => {
    hamburger.classList.toggle('active');
    navMenu.classList.toggle('active');
});

// Close mobile menu when clicking on a link
document.querySelectorAll('.nav-link').forEach(n => n.addEventListener('click', () => {
    hamburger.classList.remove('active');
    navMenu.classList.remove('active');
}));

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            const navHeight = document.querySelector('.navbar').offsetHeight;
            const targetPosition = target.offsetTop - navHeight;
            
            window.scrollTo({
                top: targetPosition,
                behavior: 'smooth'
            });
        }
    });
});

// Navbar background on scroll
window.addEventListener('scroll', () => {
    const navbar = document.querySelector('.navbar');
    if (window.scrollY > 50) {
        navbar.style.background = 'rgba(15, 23, 42, 0.98)';
    } else {
        navbar.style.background = 'rgba(15, 23, 42, 0.95)';
    }
});

// Get latest release info from GitHub API and update download button
async function fetchLatestRelease() {
    try {
        // Replace 'your-username' with actual GitHub username
        const response = await fetch('https://api.github.com/repos/your-username/wine_prefix_manager/releases/latest');
        const release = await response.json();
        
        if (release && release.tag_name && release.assets) {
            // Update version number
            const versionElement = document.getElementById('latest-version');
            if (versionElement) {
                versionElement.textContent = release.tag_name;
            }
            
            // Find AppImage asset
            const appImageAsset = release.assets.find(asset => 
                asset.name.includes('.AppImage') && asset.name.includes('x86_64')
            );
            
            if (appImageAsset) {
                // Update download button
                const downloadBtn = document.getElementById('download-btn');
                if (downloadBtn) {
                    downloadBtn.href = appImageAsset.browser_download_url;
                    downloadBtn.setAttribute('download', appImageAsset.name);
                }
                
                // Update file size
                const sizeElement = document.querySelector('.size-number');
                if (sizeElement && appImageAsset.size) {
                    const sizeInMB = (appImageAsset.size / (1024 * 1024)).toFixed(1);
                    sizeElement.textContent = `~${sizeInMB}MB`;
                }
            }
        }
    } catch (error) {
        console.log('Could not fetch latest release info:', error);
        // Fallback to local AppImage if available
        setFallbackDownload();
    }
}

// Fallback download function for local AppImage
function setFallbackDownload() {
    const downloadBtn = document.getElementById('download-btn');
    if (downloadBtn) {
        // Try to find local AppImage file
        const localAppImages = [
            '../WinePrefixManager-3.1.4-x86_64.AppImage',
            '../WinePrefixManager-3.1.3-x86_64.AppImage',
            '../WinePrefixManager-3.1.2-x86_64.AppImage'
        ];
        
        // Use the first one as fallback
        downloadBtn.href = localAppImages[0];
        downloadBtn.setAttribute('download', 'WinePrefixManager-3.1.4-x86_64.AppImage');
    }
}

// Intersection Observer for animations
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, observerOptions);

// Apply animation to elements
document.addEventListener('DOMContentLoaded', () => {
    const animatedElements = document.querySelectorAll('.feature-card, .screenshot-item, .download-box, .credit-card');
    
    animatedElements.forEach(el => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(30px)';
        el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(el);
    });
    
    // Fetch latest release info
    fetchLatestRelease();
    
    // Initialize hero carousel
    new HeroCarousel();
});

// Add copy functionality for installation commands
document.addEventListener('DOMContentLoaded', () => {
    const codeElements = document.querySelectorAll('code');
    
    codeElements.forEach(code => {
        code.style.cursor = 'pointer';
        code.title = 'Click to copy';
        
        code.addEventListener('click', () => {
            navigator.clipboard.writeText(code.textContent).then(() => {
                // Visual feedback
                const originalText = code.textContent;
                code.textContent = 'Copied!';
                code.style.color = '#10b981';
                
                setTimeout(() => {
                    code.textContent = originalText;
                    code.style.color = '';
                }, 1000);
            }).catch(err => {
                console.log('Could not copy text:', err);
            });
        });
    });
});

// Add loading state to download button
document.addEventListener('DOMContentLoaded', () => {
    const downloadBtn = document.getElementById('download-btn');
    
    if (downloadBtn) {
        downloadBtn.addEventListener('click', (e) => {
            if (!downloadBtn.href || downloadBtn.href === '#') {
                e.preventDefault();
                downloadBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Loading...';
                
                // Try to fetch latest release again
                fetchLatestRelease().then(() => {
                    setTimeout(() => {
                        downloadBtn.innerHTML = '<i class="fas fa-download"></i> Download AppImage';
                    }, 1000);
                });
                return;
            }
            
            // Add download tracking
            downloadBtn.innerHTML = '<i class="fas fa-download"></i> Downloading...';
            
            setTimeout(() => {
                downloadBtn.innerHTML = '<i class="fas fa-check"></i> Download Started';
                setTimeout(() => {
                    downloadBtn.innerHTML = '<i class="fas fa-download"></i> Download AppImage';
                }, 2000);
            }, 500);
        });
    }
});

// Add smooth reveal animation for hero elements
document.addEventListener('DOMContentLoaded', () => {
    const heroElements = document.querySelectorAll('.hero-title, .hero-description, .hero-buttons, .hero-stats');
    
    heroElements.forEach((el, index) => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(30px)';
        el.style.transition = 'opacity 0.8s ease, transform 0.8s ease';
        
        setTimeout(() => {
            el.style.opacity = '1';
            el.style.transform = 'translateY(0)';
        }, index * 200 + 300);
    });
    
    // Hero image animation
    const heroImage = document.querySelector('.hero-screenshot');
    if (heroImage) {
        heroImage.style.opacity = '0';
        heroImage.style.transform = 'scale(0.8)';
        heroImage.style.transition = 'opacity 1s ease, transform 1s ease';
        
        setTimeout(() => {
            heroImage.style.opacity = '1';
            heroImage.style.transform = 'scale(1)';
        }, 800);
    }
});

// Add scroll-to-top functionality
document.addEventListener('DOMContentLoaded', () => {
    // Create scroll-to-top button
    const scrollToTop = document.createElement('div');
    scrollToTop.innerHTML = '<i class="fas fa-arrow-up"></i>';
    scrollToTop.className = 'scroll-to-top';
    scrollToTop.style.cssText = `
        position: fixed;
        bottom: 20px;
        right: 20px;
        width: 50px;
        height: 50px;
        background: var(--primary-color);
        color: white;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        opacity: 0;
        visibility: hidden;
        transition: all 0.3s ease;
        z-index: 1000;
        box-shadow: 0 4px 15px rgba(99, 102, 241, 0.4);
    `;
    
    document.body.appendChild(scrollToTop);
    
    // Show/hide scroll-to-top button
    window.addEventListener('scroll', () => {
        if (window.scrollY > 500) {
            scrollToTop.style.opacity = '1';
            scrollToTop.style.visibility = 'visible';
        } else {
            scrollToTop.style.opacity = '0';
            scrollToTop.style.visibility = 'hidden';
        }
    });
    
    // Scroll to top on click
    scrollToTop.addEventListener('click', () => {
        window.scrollTo({
            top: 0,
            behavior: 'smooth'
        });
    });
});

// Add mobile navigation styles
document.addEventListener('DOMContentLoaded', () => {
    const style = document.createElement('style');
    style.textContent = `
        @media (max-width: 768px) {
            .nav-menu {
                position: fixed;
                left: -100%;
                top: 70px;
                flex-direction: column;
                background-color: rgba(15, 23, 42, 0.98);
                backdrop-filter: blur(10px);
                width: 100%;
                text-align: center;
                transition: 0.3s;
                box-shadow: 0 10px 27px rgba(0, 0, 0, 0.05);
                border-top: 1px solid var(--border-color);
                padding: 2rem 0;
            }
            
            .nav-menu.active {
                left: 0;
            }
            
            .nav-menu li {
                margin: 1rem 0;
            }
            
            .hamburger.active .bar:nth-child(2) {
                opacity: 0;
            }
            
            .hamburger.active .bar:nth-child(1) {
                transform: translateY(7px) rotate(45deg);
            }
            
            .hamburger.active .bar:nth-child(3) {
                transform: translateY(-7px) rotate(-45deg);
            }
        }
    `;
    document.head.appendChild(style);
});

// Add particles effect to hero section
document.addEventListener('DOMContentLoaded', () => {
    const hero = document.querySelector('.hero');
    if (!hero) return;
    
    const particlesContainer = document.createElement('div');
    particlesContainer.className = 'particles';
    particlesContainer.style.cssText = `
        position: absolute;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        pointer-events: none;
        z-index: 0;
    `;
    
    hero.appendChild(particlesContainer);
    
    // Create floating particles
    for (let i = 0; i < 50; i++) {
        const particle = document.createElement('div');
        particle.className = 'particle';
        particle.style.cssText = `
            position: absolute;
            width: 4px;
            height: 4px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 50%;
            animation: float ${Math.random() * 10 + 10}s infinite linear;
            left: ${Math.random() * 100}%;
            top: ${Math.random() * 100}%;
        `;
        
        particlesContainer.appendChild(particle);
    }
    
    // Add particle animation CSS
    const particleStyle = document.createElement('style');
    particleStyle.textContent = `
        @keyframes float {
            0% { transform: translateY(0px) rotate(0deg); }
            100% { transform: translateY(-100vh) rotate(360deg); }
        }
    `;
    document.head.appendChild(particleStyle);
});

// Hero Carousel functionality
class HeroCarousel {
    constructor() {
        this.currentSlide = 0;
        this.slides = document.querySelectorAll('.carousel-slide');
        this.indicators = document.querySelectorAll('.indicator');
        this.autoScrollInterval = null;
        this.autoScrollDelay = 4000; // 4 seconds
        
        this.init();
    }
    
    init() {
        if (this.slides.length === 0) return;
        
        // Add click handlers to indicators
        this.indicators.forEach((indicator, index) => {
            indicator.addEventListener('click', () => {
                this.goToSlide(index);
                this.resetAutoScroll();
            });
        });
        
        // Start auto-scrolling
        this.startAutoScroll();
        
        // Pause auto-scroll on hover
        const carousel = document.querySelector('.hero-carousel');
        if (carousel) {
            carousel.addEventListener('mouseenter', () => this.pauseAutoScroll());
            carousel.addEventListener('mouseleave', () => this.startAutoScroll());
        }
    }
    
    goToSlide(index) {
        // Remove active class from current slide and indicator
        this.slides[this.currentSlide].classList.remove('active');
        this.indicators[this.currentSlide].classList.remove('active');
        
        // Update current slide index
        this.currentSlide = index;
        
        // Add active class to new slide and indicator
        this.slides[this.currentSlide].classList.add('active');
        this.indicators[this.currentSlide].classList.add('active');
    }
    
    nextSlide() {
        const nextIndex = (this.currentSlide + 1) % this.slides.length;
        this.goToSlide(nextIndex);
    }
    
    startAutoScroll() {
        this.autoScrollInterval = setInterval(() => {
            this.nextSlide();
        }, this.autoScrollDelay);
    }
    
    pauseAutoScroll() {
        if (this.autoScrollInterval) {
            clearInterval(this.autoScrollInterval);
            this.autoScrollInterval = null;
        }
    }
    
    resetAutoScroll() {
        this.pauseAutoScroll();
        this.startAutoScroll();
    }
} 