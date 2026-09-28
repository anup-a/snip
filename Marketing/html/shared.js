// Lays out crops of the raw renders. Runs synchronously at the end of <body>, before the load event.
// <div class="crop" data-src="raw/x.png" data-rect="x,y,w,h" data-scale="0.8">
// A .crop inside another .crop's parent can use data-follow="#baseId" and data-lift="1.2" to sit exactly
// over the same scene rect in the base crop, scaled about its center (a "lifted" callout).
(function () {
  const num = (s) => s.split(',').map(Number);
  document.querySelectorAll('.crop').forEach((el) => {
    const [x, y, w, h] = num(el.dataset.rect);
    let s = Number(el.dataset.scale || 1);
    const follow = el.dataset.follow && document.querySelector(el.dataset.follow);
    if (follow) {
      const [bx, by] = num(follow.dataset.rect);
      const bs = Number(follow.dataset.scale || 1);
      const k = Number(el.dataset.lift || 1);
      s = bs * k;
      // Position relative to the base crop's offset parent, centered on the same scene rect.
      const cx = follow.offsetLeft + (x + w / 2 - bx) * bs;
      const cy = follow.offsetTop + (y + h / 2 - by) * bs;
      el.style.left = cx - (w * s) / 2 + 'px';
      el.style.top = cy - (h * s) / 2 + 'px';
    }
    el.style.width = w * s + 'px';
    el.style.height = h * s + 'px';
    const img = document.createElement('img');
    img.className = 'src';
    img.src = el.dataset.src;
    img.style.width = 1440 * s + 'px';
    img.style.height = 900 * s + 'px';
    img.style.left = -x * s + 'px';
    img.style.top = -y * s + 'px';
    el.prepend(img);
  });
})();
