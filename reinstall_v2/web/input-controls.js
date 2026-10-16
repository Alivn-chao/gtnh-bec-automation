// DOM dropdowns render in the same offscreen texture; native popup windows do not.
(function(){'use strict';
var open=null;
function close(){if(!open)return;open.menu.remove();open.button.setAttribute('aria-expanded','false');open=null;}
function enhance(select){
 if(select.dataset.ochdSelect)return;select.dataset.ochdSelect='1';select.classList.add('ochd-native-select');select.tabIndex=-1;
 var button=document.createElement('button');button.type='button';button.className='ochd-select';button.setAttribute('role','combobox');button.setAttribute('aria-haspopup','listbox');button.setAttribute('aria-expanded','false');
 var label=select.closest('label')||document.querySelector('label[for="'+select.id+'"]');button.setAttribute('aria-label',label?label.textContent.trim():'选择配置');select.parentNode.insertBefore(button,select.nextSibling);
 function refresh(){var option=select.options[select.selectedIndex],text=option?option.textContent:'请选择';if(button.textContent!==text)button.textContent=text;button.disabled=select.disabled;}
 select._ochdRefresh=refresh;select.addEventListener('change',refresh);refresh();
 function show(){close();var menu=document.createElement('div');menu.className='ochd-select-menu';menu.setAttribute('role','listbox');var chosen=Math.max(0,select.selectedIndex);
  function highlight(index){chosen=Math.max(0,Math.min(select.options.length-1,index));Array.from(menu.children).forEach(function(row,i){row.classList.toggle('highlight',i===chosen);});if(menu.children[chosen])menu.children[chosen].scrollIntoView({block:'nearest'});}
  function choose(index){if(select.options[index].disabled)return;select.selectedIndex=index;refresh();close();button.focus();select.dispatchEvent(new Event('change',{bubbles:true}));}
  Array.from(select.options).forEach(function(option,index){var row=document.createElement('button');row.type='button';row.className='ochd-select-option';row.textContent=option.textContent;row.setAttribute('role','option');row.setAttribute('aria-selected',String(index===select.selectedIndex));row.disabled=option.disabled;row.onclick=function(){choose(index);};menu.appendChild(row);});
  document.body.appendChild(menu);var r=button.getBoundingClientRect(),height=Math.min(230,menu.scrollHeight);menu.style.left=Math.min(innerWidth-r.width-8,r.left)+'px';menu.style.width=r.width+'px';menu.style.top=(r.bottom+height>innerHeight-8?Math.max(8,r.top-height-4):r.bottom+4)+'px';
  button.setAttribute('aria-expanded','true');open={menu:menu,button:button,select:select,highlight:highlight,choose:choose,index:function(){return chosen;}};highlight(chosen);
 }
 button.onclick=function(){if(open&&open.button===button)close();else show();};
 button.onkeydown=function(e){if(e.key==='Escape'){close();return;}if(e.key==='Tab'){close();return;}if(['ArrowDown','ArrowUp','Home','End','Enter',' '].indexOf(e.key)<0)return;e.preventDefault();var wasOpen=open&&open.button===button;if(!wasOpen)show();if(e.key==='ArrowDown')open.highlight(open.index()+1);else if(e.key==='ArrowUp')open.highlight(open.index()-1);else if(e.key==='Home')open.highlight(0);else if(e.key==='End')open.highlight(select.options.length-1);else if(wasOpen)open.choose(open.index());};
}
function refresh(){if(open&&!open.select.isConnected)close();document.querySelectorAll('select').forEach(function(select){enhance(select);select._ochdRefresh();});}
document.addEventListener('pointerdown',function(e){if(open&&!open.menu.contains(e.target)&&e.target!==open.button)close();});
document.addEventListener('scroll',function(e){if(open&&!open.menu.contains(e.target))close();},true);window.addEventListener('resize',close);
new MutationObserver(refresh).observe(document.body,{childList:true,subtree:true});window.BEC_REFRESH_SELECTS=refresh;refresh();
})();
