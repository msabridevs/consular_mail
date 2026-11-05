// Public entry: no import of staff components or Supabase browser client.
import React from 'react';
import {createRoot} from 'react-dom/client';
import Shell from './shell.jsx';
import Public from './public.jsx';
createRoot(document.getElementById('root')).render(<Shell><Public/></Shell>);
