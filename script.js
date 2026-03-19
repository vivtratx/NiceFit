// A simple script to change the text of the paragraph after a delay
const paragraph = document.querySelector('p');

setTimeout(() => {
    paragraph.textContent = 'JS is loaded!';
    paragraph.style.color = 'green';
}, 2000); // Changes text after 2 seconds
