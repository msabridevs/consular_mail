// Employee entry: published only by the separate staff Vercel project.
import React from 'react';
import {createRoot} from 'react-dom/client';
import Shell from './shell.jsx';
import Staff from './staff.jsx';
createRoot(document.getElementById('root')).render(<Shell internal><Staff/></Shell>);
