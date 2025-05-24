// Twitch Setup Page JavaScript

// Copy to clipboard functionality
function copyToClipboard(elementId) {
    const element = document.getElementById(elementId);
    const text = element.value;
    
    if (text) {
        navigator.clipboard.writeText(text).then(() => {
            // Show success feedback
            const copyBtn = element.nextElementSibling;
            const originalIcon = copyBtn.innerHTML;
            copyBtn.innerHTML = '<i class="fas fa-check"></i>';
            copyBtn.style.background = '#10b981';
            
            setTimeout(() => {
                copyBtn.innerHTML = originalIcon;
                copyBtn.style.background = '';
            }, 2000);
            
            // Show toast notification
            showToast('Copied to clipboard!', 'success');
        }).catch(err => {
            console.error('Failed to copy text: ', err);
            showToast('Failed to copy to clipboard', 'error');
        });
    } else {
        showToast('Nothing to copy!', 'warning');
    }
}

// Toast notification system
function showToast(message, type = 'info') {
    // Remove existing toast if any
    const existingToast = document.querySelector('.toast');
    if (existingToast) {
        existingToast.remove();
    }
    
    // Create toast element
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `
        <div class="toast-content">
            <i class="fas fa-${getToastIcon(type)}"></i>
            <span>${message}</span>
        </div>
    `;
    
    // Add styles
    toast.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: ${getToastColor(type)};
        color: white;
        padding: 12px 20px;
        border-radius: 8px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        z-index: 10000;
        animation: slideInFromRight 0.3s ease;
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 0.9rem;
        font-weight: 500;
    `;
    
    // Add animation keyframes if not already added
    if (!document.querySelector('#toast-animations')) {
        const style = document.createElement('style');
        style.id = 'toast-animations';
        style.textContent = `
            @keyframes slideInFromRight {
                from {
                    transform: translateX(100%);
                    opacity: 0;
                }
                to {
                    transform: translateX(0);
                    opacity: 1;
                }
            }
            @keyframes slideOutToRight {
                from {
                    transform: translateX(0);
                    opacity: 1;
                }
                to {
                    transform: translateX(100%);
                    opacity: 0;
                }
            }
        `;
        document.head.appendChild(style);
    }
    
    document.body.appendChild(toast);
    
    // Auto remove after 3 seconds
    setTimeout(() => {
        toast.style.animation = 'slideOutToRight 0.3s ease';
        setTimeout(() => {
            if (toast.parentNode) {
                toast.remove();
            }
        }, 300);
    }, 3000);
}

function getToastIcon(type) {
    switch (type) {
        case 'success': return 'check-circle';
        case 'error': return 'exclamation-circle';
        case 'warning': return 'exclamation-triangle';
        default: return 'info-circle';
    }
}

function getToastColor(type) {
    switch (type) {
        case 'success': return '#10b981';
        case 'error': return '#ef4444';
        case 'warning': return '#f59e0b';
        default: return '#6366f1';
    }
}

// Toggle switch functionality
function initializeToggleSwitches() {
    const toggleSwitches = document.querySelectorAll('.toggle-switch');
    
    toggleSwitches.forEach(toggle => {
        toggle.addEventListener('click', () => {
            toggle.classList.toggle('active');
        });
    });
}

// Smooth scroll for anchor links
function initializeSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });
}

// Form validation and feedback
function validateCredentials() {
    const clientId = document.getElementById('client-id').value.trim();
    const clientSecret = document.getElementById('client-secret').value.trim();
    
    if (!clientId || !clientSecret) {
        showToast('Please enter both Client ID and Client Secret', 'warning');
        return false;
    }
    
    // Basic format validation
    if (clientId.length < 20) {
        showToast('Client ID appears to be too short', 'warning');
        return false;
    }
    
    if (clientSecret.length < 20) {
        showToast('Client Secret appears to be too short', 'warning');
        return false;
    }
    
    return true;
}

// Simulate test connection
function testConnection() {
    if (!validateCredentials()) {
        return;
    }
    
    const testBtn = document.querySelector('.test-btn');
    const originalText = testBtn.textContent;
    
    testBtn.textContent = 'Testing...';
    testBtn.disabled = true;
    testBtn.style.opacity = '0.6';
    
    // Simulate API call
    setTimeout(() => {
        testBtn.textContent = originalText;
        testBtn.disabled = false;
        testBtn.style.opacity = '1';
        
        // Random success/failure for demo
        const success = Math.random() > 0.3;
        if (success) {
            showToast('✅ Connection successful! IGDB integration is ready.', 'success');
        } else {
            showToast('❌ Connection failed. Please check your credentials.', 'error');
        }
    }, 2000);
}

// Animate elements on scroll
function initializeScrollAnimations() {
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    }, {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    });
    
    // Observe FAQ items
    document.querySelectorAll('.faq-item, .benefit-card, .step-item').forEach(el => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(30px)';
        el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(el);
    });
}

// Add interactive hover effects
function initializeInteractiveEffects() {
    // Add particle effect to buttons on hover
    document.querySelectorAll('.btn-primary').forEach(btn => {
        btn.addEventListener('mouseenter', createParticleEffect);
    });
    
    // Add floating animation to IGDB preview card
    const igdbCard = document.querySelector('.igdb-card');
    if (igdbCard) {
        igdbCard.addEventListener('mouseenter', () => {
            igdbCard.style.transform = 'translateY(-5px) scale(1.02)';
        });
        
        igdbCard.addEventListener('mouseleave', () => {
            igdbCard.style.transform = 'translateY(0) scale(1)';
        });
    }
}

function createParticleEffect(e) {
    const button = e.target;
    const rect = button.getBoundingClientRect();
    
    for (let i = 0; i < 3; i++) {
        const particle = document.createElement('div');
        particle.style.cssText = `
            position: absolute;
            width: 4px;
            height: 4px;
            background: rgba(255, 255, 255, 0.8);
            border-radius: 50%;
            pointer-events: none;
            z-index: 1000;
            left: ${rect.left + Math.random() * rect.width}px;
            top: ${rect.top + Math.random() * rect.height}px;
            animation: particle-float 1s ease-out forwards;
        `;
        
        document.body.appendChild(particle);
        
        setTimeout(() => {
            particle.remove();
        }, 1000);
    }
}

// Add particle animation keyframes
function addParticleAnimations() {
    if (!document.querySelector('#particle-animations')) {
        const style = document.createElement('style');
        style.id = 'particle-animations';
        style.textContent = `
            @keyframes particle-float {
                0% {
                    opacity: 1;
                    transform: translateY(0) scale(1);
                }
                100% {
                    opacity: 0;
                    transform: translateY(-50px) scale(0);
                }
            }
        `;
        document.head.appendChild(style);
    }
}

// Initialize everything when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    initializeToggleSwitches();
    initializeSmoothScroll();
    initializeScrollAnimations();
    initializeInteractiveEffects();
    addParticleAnimations();
    
    // Add event listeners for buttons
    const testBtn = document.querySelector('.test-btn');
    if (testBtn) {
        testBtn.addEventListener('click', testConnection);
    }
    
    // Add input validation feedback
    const inputs = document.querySelectorAll('input[type="text"], input[type="password"]');
    inputs.forEach(input => {
        input.addEventListener('input', () => {
            if (input.value.length > 0) {
                input.style.borderColor = '#9146ff';
            } else {
                input.style.borderColor = '';
            }
        });
    });
    
    // Add focus effects to form elements
    inputs.forEach(input => {
        input.addEventListener('focus', () => {
            input.parentElement.style.transform = 'scale(1.02)';
        });
        
        input.addEventListener('blur', () => {
            input.parentElement.style.transform = 'scale(1)';
        });
    });
});

// Handle mobile navigation (if hamburger menu is used)
document.addEventListener('DOMContentLoaded', () => {
    const hamburger = document.querySelector('.hamburger');
    const navMenu = document.querySelector('.nav-menu');
    
    if (hamburger && navMenu) {
        hamburger.addEventListener('click', () => {
            hamburger.classList.toggle('active');
            navMenu.classList.toggle('active');
        });
        
        // Close menu when clicking outside
        document.addEventListener('click', (e) => {
            if (!hamburger.contains(e.target) && !navMenu.contains(e.target)) {
                hamburger.classList.remove('active');
                navMenu.classList.remove('active');
            }
        });
    }
}); 