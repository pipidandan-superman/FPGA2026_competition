"""Windows GUI for the EES-331 SD Builder."""
import os
import json
from pathlib import Path
import queue
import sys
import threading
import tkinter as tk
from tkinter import filedialog,messagebox,ttk

from builder import Builder,DEFAULT_BASE,DEFAULT_VITIS,inspect

MODES={'手动加载 PL（保留启动基线）':'manual',
       'Linux 启动后由 PYNQ 自动加载':'linux',
       'FSBL 阶段加载 PL':'fsbl'}

class Application:
    def __init__(self,root):
        self.root=root; self.events=queue.Queue(); self.busy=False; self.output=None
        root.title('EES-331 SD Builder · XSA 启动包工具')
        root.geometry('900x780'); root.minsize(790,690)
        style=ttk.Style(root)
        if 'vista' in style.theme_names(): style.theme_use('vista')
        style.configure('Title.TLabel',font=('Microsoft YaHei UI',18,'bold'))
        style.configure('Muted.TLabel',foreground='#566474')
        outer=ttk.Frame(root,padding=22); outer.pack(fill='both',expand=True)
        ttk.Label(outer,text='EES-331 SD Builder',style='Title.TLabel').pack(anchor='w')
        ttk.Label(outer,text='导入一个包含比特流的 XSA，生成配套启动文件和完整 SD 镜像。',style='Muted.TLabel').pack(anchor='w',pady=(5,15))
        ttk.Label(outer,text='板级配置：EES-331 / Zynq-7020 · Vivado/Vitis 2025.2 · PYNQ 3.0.1').pack(anchor='w',pady=(0,12))
        inputs=ttk.LabelFrame(outer,text='1  选择硬件输入',padding=12); inputs.pack(fill='x')
        self.xsa=tk.StringVar(); self.vitis=tk.StringVar(value=DEFAULT_VITIS)
        self.base=tk.StringVar(value=DEFAULT_BASE); self.dtb=tk.StringVar()
        self.controls=[]
        self.file_row(inputs,'XSA（必须包含 bitstream）',self.xsa,[('Vivado hardware export','*.xsa')],0)
        ttk.Label(inputs,text='Vivado：Export Hardware → Include bitstream。单独 .bit 文件不作为输入。',style='Muted.TLabel').grid(row=1,column=0,columnspan=3,sticky='w',pady=(7,0))
        options=ttk.LabelFrame(outer,text='2  选择导出方式',padding=12); options.pack(fill='x',pady=(12,0))
        self.mode=tk.StringVar(value=next(iter(MODES)))
        ttk.Label(options,text='PL 加载方式').grid(row=0,column=0,sticky='w')
        combo=ttk.Combobox(options,textvariable=self.mode,values=list(MODES),state='readonly',width=37)
        combo.grid(row=0,column=1,sticky='w',padx=12); self.controls.append(combo)
        self.full=tk.BooleanVar(value=True)
        full=ttk.Checkbutton(options,text='同时输出完整 .img（约 7.32 GiB；需要基础镜像）',variable=self.full)
        full.grid(row=1,column=0,columnspan=3,sticky='w',pady=(10,0)); self.controls.append(full)
        ttk.Label(options,text='始终输出启动 ZIP、文件清单和校验记录。工具只生成文件，不写 SD 卡。',style='Muted.TLabel').grid(row=2,column=0,columnspan=3,sticky='w',pady=(8,0))
        advanced=ttk.LabelFrame(outer,text='3  工具与板级配置',padding=12); advanced.pack(fill='x',pady=(12,0))
        self.file_row(advanced,'Vitis 安装目录',self.vitis,None,0,directory=True)
        self.file_row(advanced,'原版 PYNQ-Z2 v3.0.1 IMG',self.base,[('Disk image','*.img')],1)
        self.file_row(advanced,'匹配的板级 DTB（按需）',self.dtb,[('Device tree','*.dtb')],2)
        ttk.Label(advanced,text='影响 PS 外设的变化可能需要补充 DTB；驱动和外部器件配置不会从 XSA 猜测生成。',style='Muted.TLabel').grid(row=3,column=0,columnspan=3,sticky='w',pady=(5,0))
        self.force=tk.BooleanVar(value=False)
        force=ttk.Checkbutton(advanced,text='即使 PS 未变，也重新生成 FSBL/BSP',variable=self.force)
        force.grid(row=4,column=0,columnspan=3,sticky='w',pady=(7,0)); self.controls.append(force)
        actions=ttk.Frame(outer); actions.pack(fill='x',pady=14)
        self.check=ttk.Button(actions,text='检查 XSA / 配置差异',command=self.start_inspect)
        self.check.pack(side='left'); self.controls.append(self.check)
        self.build=ttk.Button(actions,text='生成启动包',command=self.start_build)
        self.build.pack(side='left',padx=10); self.controls.append(self.build)
        self.open=ttk.Button(actions,text='打开输出目录',command=self.open_output,state='disabled')
        self.open.pack(side='right')
        self.status=tk.StringVar(value='请选择包含比特流的 XSA。')
        ttk.Label(outer,textvariable=self.status).pack(anchor='w')
        self.progress=ttk.Progressbar(outer,mode='indeterminate'); self.progress.pack(fill='x',pady=7)
        logframe=ttk.Frame(outer); logframe.pack(fill='both',expand=True)
        self.log=tk.Text(logframe,height=10,wrap='word',font=('Consolas',10),bg='#f4f7fa',relief='flat',padx=10,pady=10)
        scroll=ttk.Scrollbar(logframe,command=self.log.yview); self.log.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right',fill='y'); self.log.pack(side='left',fill='both',expand=True)
        self.log.configure(state='disabled')
        root.protocol('WM_DELETE_WINDOW',self.close)
        root.after(100,self.poll)

    def file_row(self,parent,label,variable,filetypes,row,directory=False):
        ttk.Label(parent,text=label).grid(row=row,column=0,sticky='w',pady=4)
        entry=ttk.Entry(parent,textvariable=variable); entry.grid(row=row,column=1,sticky='ew',padx=(12,8))
        def choose():
            path=filedialog.askdirectory() if directory else filedialog.askopenfilename(filetypes=filetypes)
            if path: variable.set(path)
        button=ttk.Button(parent,text='选择…',command=choose); button.grid(row=row,column=2)
        self.controls.extend([entry,button]); parent.columnconfigure(1,weight=1)

    def append(self,line):
        self.log.configure(state='normal'); self.log.insert('end',str(line)+'\n'); self.log.see('end'); self.log.configure(state='disabled')

    def set_busy(self,value):
        self.busy=value
        for control in self.controls:
            control.configure(state='disabled' if value else ('readonly' if isinstance(control,ttk.Combobox) else 'normal'))
        if value: self.progress.start(12)
        else: self.progress.stop()

    def launch(self,operation):
        if self.busy: return
        if not self.xsa.get().strip(): messagebox.showerror('需要 XSA','请选择包含 bitstream 的 XSA。'); return
        self.set_busy(True); self.status.set('正在处理…')
        def worker():
            try: self.events.put(('done',operation()))
            except Exception as exc: self.events.put(('error',str(exc)))
        threading.Thread(target=worker,daemon=True).start()

    def start_inspect(self):
        path=self.xsa.get()
        def operation():
            result=inspect(path)
            self.events.put(('line','器件：'+result['part']+'；位流：'+result['bitstream_name']))
            self.events.put(('line','XSA SHA256：'+result['xsa_sha256']))
            self.events.put(('line',f"PS 配置变化：{len(result['ps_changes'])} 项；板级 DT 待核对：{len(result['device_tree_review_changes'])} 项。"))
            for c in result['ps_changes']:
                self.events.put(('line',f"{c['parameter']}: {c['before']} → {c['after']}"))
            return {'kind':'inspect','status':result['status']}
        self.launch(operation)

    def start_build(self):
        settings=dict(xsa=self.xsa.get(),vitis=self.vitis.get(),base=self.base.get(),dtb=self.dtb.get(),
                      mode=MODES[self.mode.get()],full_image=self.full.get(),rebuild_fsbl=self.force.get(),
                      log=lambda line:self.events.put(('line',line)))
        def operation():
            result=Builder(**settings).execute()
            return {'kind':'build','output':result['output']}
        self.launch(operation)

    def poll(self):
        while not self.events.empty():
            kind,value=self.events.get()
            if kind=='line': self.append(value)
            elif kind=='error':
                self.set_busy(False); self.status.set('未导出：请根据提示处理输入或配置。')
                self.append('错误：'+value); messagebox.showerror('构建未完成',value)
            else:
                self.set_busy(False)
                if value['kind']=='build':
                    self.output=value['output']; self.open.configure(state='normal')
                    self.status.set('导出及文件校验完成；新硬件配置仍需板测。')
                    self.append('输出：'+self.output)
                else:
                    self.status.set('需要补充匹配的板级 DTB。' if value['status']=='NEEDS_BOARD_DTB' else 'XSA 检查通过，可以生成启动包。')
        self.root.after(100,self.poll)

    def open_output(self):
        if self.output and Path(self.output).is_dir(): os.startfile(self.output)

    def close(self):
        if self.busy:
            messagebox.showinfo('正在构建','正在生成或校验输出，请等待完成后关闭窗口。')
        else: self.root.destroy()

def main():
    root=tk.Tk(); Application(root); root.mainloop()

if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--self-test':
        from builder import verify_assets
        from pyfatfs.PyFatFS import PyFatFS
        import importlib.metadata
        verify_assets()
        root=tk.Tk(); root.withdraw(); window=Application(root); root.update_idletasks(); root.destroy()
        Path(sys.argv[2]).write_text(json.dumps({'result':'FROZEN_GUI_SELF_TEST_PASS',
            'pyfatfs':importlib.metadata.version('pyfatfs'),'fs':importlib.metadata.version('fs')}))
    elif len(sys.argv)==3 and sys.argv[1]=='--build-config':
        config=json.loads(Path(sys.argv[2]).read_text(encoding='utf-8-sig'))
        result=Builder(**config,log=lambda line:None).execute()
        Path(sys.argv[2]+'.result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    else:
        main()
